package RDF::Base::Search;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Search - Search directly in DB

=cut

use 5.010;
use strict;
use warnings;
use base 'Clone'; # gives method clone()
use constant BINDVALS   =>  0;

use Carp qw( cluck confess croak carp shortmess longmess );
use Time::HiRes qw( time );
use List::Util qw( min );
use Scalar::Util qw( refaddr );
#use Sys::SigAction qw( set_sig_handler );
use Encode; # encode decode

use Para::Frame::Utils qw( throw debug datadump ); #);
use Para::Frame::Reload;
use Para::Frame::L10N qw( loc );
use Para::Frame::Worker;

use RDF::Base::Utils qw( valclean query_desig parse_form_field_prop alphanum_to_id parse_propargs ); #);
use RDF::Base::Resource;
use RDF::Base::Pred;
use RDF::Base::List;
use RDF::Base::Arc::Lim;


=head1 DESCRIPTION

Represents one search project.

CGI query parameters reserved for use with some methods are:

  limit
  use_cached
  query
  remove
  revprop_...
  prop_...
  order_by...
  path_...
  replace


=cut


our %DBSTAT;


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any Search object.

=cut

##############################################################################

=head2 new

=cut

sub new
{
    my ($this, $args) = @_;
    my $class = ref($this) || $this;
    my $search = bless {}, $class;
    $search->reset($args);
    return $search;
}

#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

##############################################################################

=head2 size

Shortcut for C<$search-E<gt>result-E<gt>size> but returns undef if no
search result exist.

=cut

sub size
{
    if( my $res = $_[0]->{'result'} )
    {
	return $res->size;
    }
    else
    {
	return undef;
    }
}

##############################################################################

=head2 result

Returns a L<Para::Frame::List>

=cut

sub result
{
    my( $search ) = @_;

    # May have a cb search result instead...
    my $res = $search->{'result'} or return RDF::Base::List->new_empty();

#    debug "Returning search result list ".refaddr( $res );

    confess(datadump($res)) if ref $res eq 'ARRAY';
    confess(datadump($search)) unless $res;


## Use Search Collection Result
#    my $limit = 20;
#    if( my $req = $Para::Frame::REQ )
#    {
#	my $user = $req->user;
#	if( $user and $req->is_from_client )
#	{
#	    my $q = $req->q;
#	    $limit = $q->param('limit') || 10;
#	    $limit = min( $limit, PAGELIMIT ) unless $user->has_root_access;
#	}
#    }
#    $res->set_page_size( $limit );

    return $res;
}

##############################################################################

=head2 set_result

Take care not to try to recalculate the result from search obj if the
result is set by other method.

=cut

sub set_result
{
    my( $search, $list ) = @_;

    unless( ref $list )
    {
	die "Malformed list: $list";
    }

    return $search->{'result'} = RDF::Base::List->new($list);
}

##############################################################################

=head2 reset_result

=cut

sub reset_result
{
    $_[0]->{'result'} = undef;
}

##############################################################################

=head2 result_url

=cut

sub result_url
{
    $_[0]->{'result_url'} = $_[1] if defined $_[1];
    return $_[0]->{'result_url'} ||
      $Para::Frame::REQ->site->home->url_path_slash;
}

##############################################################################

=head2 form_url

=cut

sub form_url
{
    $_[0]->{'form_url'} = $_[1] if defined $_[1];
    return $_[0]->{'form_url'} ||
      $Para::Frame::REQ->site->home->url_path_slash;
}

##############################################################################

=head2 add_stats

  $s->add_stats

  $s->add_stats($bool)

Gets/sets a boolean value if this search should be added to the
statistics using L<RDF::Base::Resource/log_search>.

=cut

sub add_stats { $_[0]->{'add_stats'} = $_[1] if defined $_[1]; $_[0]->{'add_stats'} }

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

##############################################################################

=head2 cached_search_result

=cut

sub cached_search_result
{
    my( $search, $args ) = @_;

    my $req = $Para::Frame::REQ;
    if( my $id = $req->q->param('use_cached') )
    {
	return $req->user->session->list($id);
    }

    $search->reset();
    $search->modify($args);
    $search->execute();

    my $list = $search->result;
    $list->store;
    return $list;
}

##############################################################################

=head2 reset

=cut

sub reset  # Keep this hash thingy but clear it's contents
{
    my( $search, $args ) = @_;

    $search->remove_node;

    foreach my $key ( keys %$search )
    {
	delete $search->{$key};
    }

    $search->{'query'}{'order_by'} = [];

    $args ||= {};


#    # Set MAXLIMIT.
#    # Start limited. Set it wider if search is restricted to something
#
#    if( $args->{'maxlimit'} )
#    {
#	$search->{'maxlimit'} = $args->{'maxlimit'};
#	debug "*********** Maxlimit set\n";
#    }
#    else
#    {
#
#	# Try to take all the search result and do limitations
#	# afterwards by pagelimit and pagesize limit
#	#
#	$search->{'maxlimit'} = TOPLIMIT;
#
#
##	# searching will be done before we have a user obj
##	if( my $user = $Para::Frame::REQ->user )
##	{
##	    $search->{'limit_display'} = $user->level >= 20 ? TOPLIMIT : MAXLIMIT;
##	    debug "************** limit_display set to ".$search->{'limit_display'} ;
##	}
#    }

    debug 3, "Search object resetted";
    return $search;
}

##############################################################################

=head2 query_setup

=cut

sub query_setup
{
    my( $search ) = @_;

    my $props = $search->rev_query();
    my $query = "";
    foreach my $prop ( keys %$props )
    {
	my $values = $props->{$prop};

	unless( ref $values and (ref $values eq 'ARRAY' or
				 ref $values eq 'RDF::Base::List' )
	      )
	{
	    $values = [$values];
	}


	foreach my $value ( @$values )
	{
	    $query .= $prop .' '. $value ."\n";
	}
    }

    my $q = $Para::Frame::REQ->q;
    $q->param('query', encode("UTF-8", $query));

    return $query;
}

##############################################################################

=head2 form_setup

=cut

sub form_setup
{
    my( $search ) = @_;
    #
    # Set up query params from search object

    my $q = $Para::Frame::REQ->q;
    my $props = $search->rev_query('full');

    foreach my $prop ( keys %$props )
    {
	my( @values ) = $q->param($prop);
	my $newvals = $props->{$prop};
	$newvals = [$newvals] unless ref $newvals;
#	debug "$prop: have @values adding @{$newvals}";

	# Get unique values in list
	my %vals = map{ $_,1 } @values;
	foreach my $val ( @$newvals )
	{
	    next unless defined $val;
	    next if $vals{$val} ++;
	    push @values, encode("UTF-8", $val);
	}

	$q->param( -name=>$prop, -values=> \@values );
    }

    # Return true if search is non-empty
    return scalar %$props;
}

##############################################################################

=head2 modify_from_query

  $search->modify_from_query

Recognized parts are:

  revprop
  rev
  prop
  parse
  remove

remove calls L</broaden>.
Example:
  [% FOREACH ckey IN crits.keys %]
     [% NEXT UNLESS ckey == 'departure' %]
     [% crit = crits.$ckey %]
     [% FOREACH foo IN crit.prop %]
        [% hidden("remove", "prop_${foo.key}") %]
     [% END %]
  [% END %]

If parse is set to value, the value are parsed recognizing:

  value
  rev
  arclim
  clean
  match
  prio
  type
  scof

=cut

sub modify_from_query
{
    my( $search ) = @_;

    my $q = $Para::Frame::REQ->q;

    my %props;
    foreach my $param ( $q->param() )
    {
	if( $param eq 'remove' )
	{
	    foreach my $remove ( $q->param($param) )
	    {
		my( $type, $target ) = split(/_/, $remove, 2 );
		$search->broaden( $type, $target );
	    }
	}


	#filter out other params
	next unless $param =~ /^(revprop_|prop_|order_by|path_)/;

	my( @vals ) =  $q->param($param);

#	debug "Parsing $param";

	my $arg = parse_form_field_prop($param);

#	debug "got: ".query_desig( $arg );

	my $key;
	if( $arg->{'revprop'} )
	{
	    $key = "rev_" . $arg->{'revprop'};
	}
	elsif( $arg->{'rev'} )
	{
	    $key = "rev_" . $arg->{'rev'};
	}
	elsif( $arg->{'prop'} )
	{
	    $key = $arg->{'prop'};
	}
	else
	{
	    confess "Param $param not recognized";
	}

	my $parse_value = 0;
	if( ($arg->{'parse'}||'') eq 'value' )
	{
	    $parse_value = 1;
	}

        my $type = $arg->{'type'};
        my $scof = $arg->{'scof'};

	# Add values
	foreach my $val ( @vals )
	{
	    my @invals;
	    if( ref $val eq 'ARRAY')
	    {
		@invals = @$val;
	    }
	    else
	    {
		@invals = $val;
	    }


	    ## Do not add empty fields from the form (but ad '0')

#	    debug "Handling search key $key";

	    my @values = grep $_ ne '', grep defined, @invals;
	    next unless @values;


#	    debug "Setup search key $key\n"; ### DEBUG
	    if( $parse_value )
	    {
		foreach my $val ( @values )
		{
		    my $varg = parse_form_field_prop($val);
		    my $val_out = $varg->{'value'};
		    my $key_out = $key;

		    if( $varg->{'rev'} )
		    {
			$key_out = 'rev_'.$key_out;
		    }

		    if( my $arclim = $varg->{'arclim'} || $arg->{'arclim'} )
		    {
			$key_out .= '_'. $arclim;
		    }

		    if( $varg->{'clean'} || defined($arg->{'clean'}) )
		    {
			$key_out .= '_clean';
		    }

		    if( my $match = $varg->{'match'} || $arg->{'match'} )
		    {
			$key_out .= '_'. $match;
		    }

		    if( my $prio = $varg->{'prio'} || $arg->{'prio'} )
		    {
			$key_out .= '_'. $prio;
		    }

		    unless( length($val_out) )
		    {
			confess "No value part found in param $val";
		    }



		    push @{ $props{$key_out} }, $val_out;
		}
	    }
	    else
	    {
		if( my $arclim = $arg->{'arclim'} )
		{
		    $key .= '_'. $arclim;
		}

		if( defined($arg->{'clean'}) )
		{
		    $key .= '_clean';
		}

		if( my $match = $arg->{'match'} )
		{
		    $key .= '_'. $match;
		}

		if( my $prio = $arg->{'prio'} )
		{
		    $key .= '_'. $prio;
		}

		push @{ $props{$key} }, @values;
	    }
	}

        if( $props{$key} and ($type or $scof) )
        {
            my $val = $props{$key};
            my $crit = {'predor_name_-_code_-_name_short_clean' => $val };
            if( $type )
            {
                $crit->{is} = $type;
            }

            if( $scof )
            {
                $crit->{scof} = $scof;
            }

            # TODO: Maby using argument 'singular=0' for looking up
            # criterion in a later stage

            $props{$key} = RDF::Base::Resource->get($crit);
        }
    }

#    debug datadump(\%props);

    $search->modify( \%props );
}

##############################################################################

=head2 broaden

Broaden never keeps predor-preds... Bug to fix later...

=cut

sub broaden # removes targets from searchy type
{
    my( $search, $type, $target ) = @_;

    $search->remove_node;

    if( UNIVERSAL::isa( $target, 'RDF::Base::Literal' ) )
    {
	$target = $target->literal;
    }

    if( $type eq 'prop' ) # a specific property
    {
	my @new;
	my $old = $search->{'query'}{'prop'};

	debug(2, "Replace $type $target");

	foreach my $crit ( values %$old )
	{
	    debug( 2, "Compare with $crit->{'key'}");

	    if( $crit->{'key'} ne $target )
	    {
		push @new, $crit;
	    }
	}

	$search->{'query'}{'prop'} = {};
	foreach my $crit ( @new )
	{
	    $search->add_prop( $crit );
	}
    }
    elsif( $type eq 'props' ) # a specific property
    {
	my @new;
	my $old = $search->{'query'}{'prop'};

	$target =~ s/^rev//;

	debug( 2, "Replace $type $target");

	foreach my $crit ( values %$old )
	{
	    my $preds = $crit->{'pred'};
	    my $predkey;
	    if( $preds->size > 1 )
	    {
		my @pred_names = map $_->plain, $preds->as_array;
		$predkey = 'predor_'.join('_-_', @pred_names);
	    }
	    else
	    {
		$predkey = $preds->get_first_nos->plain;
	    }

	    debug( 0, sprintf("-- Comparing %s with %s", $predkey, $target));
	    if( $predkey ne $target )
	    {
		push @new, $crit;
	    }
	}

	$search->{'query'}{'prop'} = {};
	foreach my $crit ( @new )
	{
	    $search->add_prop( $crit );
	}
    }
    elsif( $type eq 'path' )
    {
	delete $search->{'query'}{'path'}{$target};
    }
    else
    {
	die "not implemented: $type";
    }

    $search->reset_sql;
}

##############################################################################

=head2 modify

  $search->modify( \%crits )

  $search->modify( \%crits, \%args )

C<%crits> consists of key/value pairs. The values can be an arrayref,
a L<RDF::Base::List> or a single value. For a list, we search for
nodes having at least one of the listed values.

Each value can be a L<RDF::Base::Resource> object, a ref to a hash
containing an C<id> key or a ref to a hash in the form of a
subrequest. The id will be extracted by calling
L<RDF::Base::Resource/get_id>.

Empty values are valid. (That includes fales values, empty strings and
undef values or undef objects.)

The C<%args> is used for all C<%crits>.

  private: Can be used to hide some properties in the presentation of
a search object.

  clean: Sets the clean property for each criterion.

  arclim: Only search for nodes where the properties meets the arclim

The keys are built up of parts used to describe the type of search
part (search criterion).

The search format should be compatible with L<RDF::Base::List/find>.

=head3 path

currently only used in one place in search/fairs.tt

This type of search may be removed removed in the future

=head3 order_by

Calls L</order_add> with the given values.

This functionality may be moved to L</modify_from_query>.

=head3 maxlimit

Limits search result to the first C<maxlimit> results

=head3 Main search key format

  <rev> _ <pred> _ <arclim> _ <clean> _ <comp> _ <prio>

All parts except C<pred> is optional.

Example: rev_in_region_explicit_clean_begins_2

Perl does a non-greedy match to extract all the parts from the key.

C<rev>: C<rev> indicates a reverse property.

C<pred>: Any predicate name.

C<arclim>: Any of L<RDF::Base::Arc::Lim/limflag>.  Those are criterions for
the arcs to match. This will override the value of C<args.arclim>.
Defaults to L<RDF::Base::Arc/active>.

C<clean>: If C<clean>, uses the clean version of strings in the
search. This will override the value of C<args.clean>. Defaults to
false.

C<comp>: Any of C<eq>, C<like>, C<begins>, C<gt>, C<lt>, C<ne>,
C<exist>.

C<prio>: One or more digits.



Returns: 1

=cut

sub modify
{
    my( $search, $props, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    $search->remove_node;

#    Para::Frame::Logging->this_level(4);
    debug 3, shortmess "modify search ".query_desig( $props ); ### DEBUG
    unless( ref $props eq 'HASH' )
    {
	confess "modify called with faulty props: ".datadump($props);
    }

    $args ||= {};

    my $private = $args->{'private'} || 0;

    if( my $arclim_in = $args->{'arclim'} )
    {
	$search->set_arclim( $arclim_in );
    }

    if( my $aod = $args->{arc_active_on_date} )
    {
	$search->set_arc_active_on_date($aod);
    }


    my $c_resource = RDF::Base::Resource->get_by_label('resource');


    # Handling sub-criterions
    #
    # Those that will give only one result should be integrated in the
    # SQL search. Others could be added as filters on the result.

    my %filter;


    foreach my $key ( keys %$props )
    {
	my $query = $props->{ $key };
        if( ref $query eq 'HASH' )
        {
            if( $query->{'id'} )
            {
                $props->{ $key } = $query->{'id'};
                next;
            }

#            debug "SUBQUERY: ".query_desig($query);

            my $sub = RDF::Base::Search->new($args);
            $sub->modify($query, $args);
            $sub->execute({%$args,maxlimit=>2});
            my $size = $sub->result->size;
            if( $size < 1 )
            {
                throw('notfound',"Sub-criterion gave no result",
                      query_desig($query));
            }
            elsif( $size > 1 )
            {
                my $req = $Para::Frame::REQ;
                if( $req and $req->is_from_client )
                {
                    if( my $item_id = $req->q->param('route_alternative') )
                    {
                        ### TODO: FIXME: Find a better selection method
                        debug "*********** May use route_alternative $item_id";
                        my $item = RDF::Base::Resource->get($item_id );
                        if( $sub->result->contains($item) )
                        {
                            debug "Incorporating result from subquery for $key";
                            $props->{ $key } = $sub->result->get_first_nos->id;
                            next;
                        }
                    }
                }

                debug "Moving subquery for $key to post-filter";
#                debug query_desig( $props->{ $key } );
                $filter{ $key } = delete $props->{ $key };
            }
            else
            {
                debug "Incorporating result from subquery for $key";
                $props->{ $key } = $sub->result->get_first_nos->id;
            }
        }
	elsif( $key =~ /^([^\.]+)\./ )
	{
	    debug "Moving multistep query $key to filter";

	    # Keep first part. Put the rest in filter
	    my $first = $1;
	    $filter{ $key } = delete $props->{ $key };
	    $first =~ s/[\{\[]+.*//; # Remove special formatting
	    $props->{ $first . '_exist' } = 1;

	}
    }

    unless( scalar keys %$props )
    {
        debug "  Filter is ".query_desig( \%filter );
        debug "Tried to do a search with no props";
    }

    foreach my $key ( keys %$props )
    {
	# Set up values supplied
	#
	my $valref = parse_values($props->{ $key });
	my @values = @$valref;

	confess datadump $props if $key =~ /^0x/; ### DEBUG


	# The filtering out of empty values is now in modify_by_query

	if( $key =~ m/^path_(.+?)(?:_(clean))?(?:_Prio(\d+))?$/ )
	{
	    # We split the steps in execute stage

	    my $path  = $1;
	    my $clean = $2 || $args->{'clean'} || 0;
	    my $prio  = $3 || 5;  # NOT USED ?!?!

	    debug 3, "Path is $path";
	    debug 3, "Clean is $clean";
	    debug 3, "Prio is $prio";

#		debug "Adding path $path\n";
	    $search->{'query'}{'path'}{$path} ||= [];

	    my $rec =
	    {
	     path => $path,
	     prio => $prio,
	     clean => $clean,
	     values => \@values,
	    };

	    push @{$search->{'query'}{'path'}{$path}}, $rec;
	}
	elsif( $key eq 'order_by' )
	{
	    $search->order_add( \@values );
	}
	elsif( $key eq 'maxlimit' )
	{
            $search->{'maxlimit'} = $values[0];
	}
	elsif( $key =~ m/^(subj|pred|coltype)$/ )
	{
	    my $qarc = $search->{'query'}{'arc'} ||= {coltype=>undef};

	    if( $key eq 'subj' )
	    {
		my $subjl = $qarc->{'subj'} ||= [];
		foreach my $subj_id ( @values )
		{
		    push @$subjl, $subj_id;
		}
	    }
	    elsif( $key eq 'pred' )
	    {
		my $predl = $qarc->{'pred'} ||= [];
		my $ocoltype = $qarc->{'coltype'};
		foreach my $pred_in ( @values )
		{
		    my $pred = RDF::Base::Pred->get( $pred_in );
		    my $coltype = $pred->coltype;
		    if( $ocoltype and ($coltype ne $ocoltype) )
		    {
			confess "Coltype mismatch1: $coltype ne $ocoltype";
		    }
		    $qarc->{'coltype'} = $coltype;

		    push @$predl, $pred->id;
		}
	    }
	    elsif( $key eq 'coltype' )
	    {
		my $ocoltype = $qarc->{'coltype'};
		foreach my $val ( @values )
		{
		    if( $ocoltype and ($val ne $ocoltype) )
		    {
			confess "Coltype mismatch2: $val ne $ocoltype";
		    }
		    $qarc->{'coltype'} = $val;
		}
	    }

	    # Parse obj and value after coltype established
	}
	elsif ($key =~ m/^(rev_)?(.*?)(?:_(direct|indirect|explicit|implicit))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/x)
	{
	    my $rev    = $1;
	    my $pred   = $2;
	    my $predref;
	    my $type;
	    my $arclim = $3 || undef; # defaults to search arclim on execute
	    my $clean  = $4 || $args->{'clean'} || 0;
	    my $match  = $5 || 'eq';
	    my $prio   = $6; #Low prio first (default later)

	    if( $pred eq 'is' ) # TODO: Generalize
	    {
		my( @newvals, $changed );
		foreach my $val ( @values )
		{
		    if( $val eq 'arc') # plain string
		    {
			# Set this up as a arc search
			$search->{'query'}{'arc'} ||= {coltype=>undef};
			$changed ++;
		    }
		    elsif( $values[0] eq $c_resource )
		    {
			# used in RDF::Base::Resource->find_by_anything()
			$changed ++;
		    }
		    else
		    {
			push @newvals, $val;
		    }
		}

		if( $changed )
		{
		    if( @newvals )
		    {
			@values = @newvals;
		    }
		    else
		    {
			next;
		    }
		}
	    }
	    elsif( $pred =~ /^(value|obj)$/ )
	    {
		# Don't want to giva value a special_id in RDF::Base::Pred
		debug 2, "Adding search meta '$pred'";
		$search->{'meta'}{$pred} ||= [];
		push @{$search->{'meta'}{$pred}},
		{
		 match => $match,
		 values => \@values,
		 prio => $prio,   # Low prio first
		 pred_name => $pred,
		 pred => undef,
		};

		next;
	    }
	    elsif( $pred =~ s/^predor_// )
	    {
		my( @prednames ) = split /_-_/, $pred;
		my( @preds ) = map RDF::Base::Pred->get($_), @prednames;
		$predref = \@preds;

		# Assume no type mismatch between alternative preds
		$type = $preds[0]->coltype;
	    }
	    elsif( $pred =~ /^count_pred_(.*)/ )
	    {
		confess "not implemented: $pred";
	    }
	    elsif( $pred =~ /\./ )
	    {
		confess "not implemented: $pred";
	    }
	    elsif( $pred =~ /\{/ )
	    {
		confess "not implemented: $pred";
	    }
	    elsif( $pred =~ /\[/ )
	    {
		confess "not implemented: $pred";
	    }

	    unless( $predref )
	    {
		# Must also take dynamic preds like 'is'
                #debug "Looking up pred $pred";
		$pred = RDF::Base::Pred->get( $pred );
		$type = $pred->coltype;
		$predref = [$pred];
	    }

	    if( (not ref $values[0] or
		 UNIVERSAL::isa($values[0],'RDF::Base::Literal::String') ) and
		($values[0] eq '*') )
	    {
		$match = 'exist';
	    }

	    if( $match eq 'exist' )
	    {
		if( $values[1] )
		{
		    confess "Can't use more than one value for exist";
		}

		if( $values[0] )
		{
		    @values = (1);
		}
		else
		{
		    @values = (0);
		}
	    }
	    elsif( $type eq 'valtext' )
	    {
		if( $clean )
		{
		    $type = 'valclean';
		}
	    }
	    elsif( $type eq 'obj' )
	    {
		#### FIXME: This part not used anymore. Handled above


		# The obj part can be specified in several ways
		#
		my @new;
		foreach my $val ( @values )
		{
		    if( ref $val and UNIVERSAL::isa( $val, 'RDF::Base::Object' ) )
		    {
			unless( $val->defined )
			{
			    $val = undef;
			}
		    }

		    if( defined $val and length $val )
		    {
			push @new, RDF::Base::Resource->get( $val )->id;
		    }
		    else
		    {
			push @new, undef;
		    }
		}
		@values = @new;
	    }
	    elsif( $type eq 'valdate' )
	    {
		my @new;
		foreach my $val ( @values )
		{
		    push @new, $RDF::dbix->format_datetime($val);
		}
		@values = @new;
	    }

	    if( (not @values) and ($match ne 'exist') )
	    {
		throw('incomplete', longmess("Values missing: ".datadump $search->{'query'}{'prop'}));
	    }

	    if( $rev )
	    {
		$type = 'subj';
	    }

	    my $pred_name = $predref->[0]->label;
	    if( $pred_name =~ m/^(id|id_alphanum|label|created|updated|owned_by|read_access|write_access|created_by|updated_by|arc_weight)$/ )
	    {
		if( @$predref > 1)
		{
		    confess "predor not supported for $pred_name";
		}

		debug 2, "Adding search meta '$pred_name'";
		$search->{'meta'}{$pred_name} ||= [];
		push @{$search->{'meta'}{$pred_name}},
		{
		 match => $match,
		 values => \@values,
		 prio => $prio,   # Low prio first
		 pred_name => $pred_name,
		 pred => RDF::Base::List->new($predref),
		};
	    }
	    elsif( $pred_name =~ m/^(obj|value)$/ )
	    {
		die "implement me: $pred_name";
	    }
	    else
	    {
		$search->add_prop({
				   rev => $rev,
				   pred => RDF::Base::List->new($predref),
				   type => $type,
				   match => $match,
				   clean => $clean,
				   values => \@values,
				   prio => $prio,   # Low prio first
				   private => $private,
				   arclim => $arclim,
				  });
	    }
	}
	else
	{
	    die "wrong format in search find: $key\n";
	}
    }

    $search->reset_sql;

    my @unhandled = qw(owned_by read_access write_access);
    my $meta = $search->{'meta'};

    # Is this an arc search?
    if( my $qarc = $search->{'query'}{'arc'} )
    {
#	debug "This is an arc search";
	my $values;
	if( $props->{'obj'} )
	{
	    # Used by RDF::Base::Rule/remove_infered_rel
	    # ... the obj may be a value node of a literal.
	    $qarc->{'coltype'} ||= 'obj';
	    $qarc->{'obj'} = parse_values($props->{'obj'});
	}
	elsif( $props->{'value'} )
	{
	    $values = parse_values($props->{'value'});
	    my $coltype = $qarc->{'coltype'};

	    if( $coltype )
	    {
		unless( $coltype =~ /^(obj|val.+)$/ )
		{
		    confess "Invalid coltype: $coltype";
		}
	    }
	    else
	    {
		confess "Coltype must be indicated";
	    }

	    $qarc->{$coltype} = $values;
	}

	foreach my $key (qw(created_by updated_by created updated id obj value arc_weight))
	{
	    if( $meta->{$key} )
	    {
		foreach my $m (@{$meta->{$key}})
		{
		    if( $m->{'match'} ne 'eq' )
		    {
			confess "Matchtype $m->{'match'} not implemented for arc $key";
		    }
		    $qarc->{$key} = $m->{'values'};
		}
	    }
	}

	foreach my $key (@unhandled)
	{
	    if( $props->{$key} )
	    {
		confess "Search key $key not implemented";
	    }
	}

    }
    else
    {
	if( $meta->{'id_alphanum'} )
	{
	    my $alphanum = $meta->{'id_alphanum'}[0]{'values'}[0];
	    my $id = alphanum_to_id( $alphanum );
	    unless( $id )
	    {
		throw('validation',"Invalid id_alphanum");
	    }

	    my $pred = RDF::Base::Pred->get('id');
	    $meta->{'id'} ||= [];
	    push @{$meta->{'id'}},
	    {
	     match => $meta->{'id_alphanum'}[0]{'match'},
	     values => [ $id ],
	     prio => $meta->{'id_alphanum'}[0]{'prio'},
	     pred_name => 'id',
	     pred => RDF::Base::List->new([$pred]),
	    };
	}

	if( $meta->{'id'} )
	{
	    foreach my $mid (@{$meta->{'id'}})
	    {
		$search->add_prop({
				   rev => 0,
				   pred => $mid->{'pred'},
				   type => 'valfloat',
				   match => $mid->{'match'},
				   clean => 0,
				   values => $mid->{'values'},
				   prio => ($mid->{'prio'}||1),
				   private => 0,
				   arclim => undef,
				  });
	    }
	}

	foreach my $key (qw(created_by updated_by created updated label ))
	{
	    if( my $mlist = $meta->{$key} )
	    {
		my $snode = $search->{'query'}{'node'} ||= [];
		push @{$snode}, @{$mlist};
	    }
	}

	foreach my $key (@unhandled)
	{
	    if( $props->{$key} )
	    {
		confess "Search key $key not implemented";
	    }
	}
    }

    if( keys %filter )
    {
        $search->{'filter'} = \%filter;
    }

    return 1;
}

##############################################################################

=head2 execute

  $s->execute(\%args)

Args MUST be a hashref.

=cut

sub execute
{
    my( $search, $args ) = @_;

#    Para::Frame::Logging->this_level(4);

    my( $sql, $values, $min_prio ) = $search->build_sql;
    unless( $sql )
    {
	debug "Executing an empty search...";
	return '';
    }

    my $result;
    my $maxlimit = $search->{'maxlimit'};

    if( $min_prio > 4 )
    {
	$Para::Frame::REQ->note(loc("Searching")."...");
    }

    if( $min_prio > 2 and not $RDF::Base::IN_SETUP_DB  ) # was 4
    {
#	debug "Search is to heavy! Runs in background";
#	debug $search->sysdesig;
#	debug $search->sql_sysdesig;

#	my $req = $Para::Frame::REQ;
#	my $fork = $req->create_fork;
#	if( $fork->in_child )
#	{
#	    $fork->return( $search->get_result($sql, $values, 240, $maxlimit) ); # 60
#	}
#	my $fres = $fork->yield;
#	$result = $fres->message;

	( $result ) = Para::Frame::Worker->method('RDF::Base::Search', 'get_result', $sql, $values, 240, $maxlimit); # 60


    }
    else
    {
#	debug "MIN PRIO = $min_prio";
	if( debug > 4 )
#	if( $search->{'query'}{'arc'} )
#	if(1)
#	if( @{$search->{'query'}{'order_by'}} )
	{
#	    debug datadump($search->{'prop'}, 2);
	    debug 0, $search->sysdesig;
#	    debug 0, $search->sql_sysdesig;
	}
#	debug "fast search";

	$result = $search->get_result($sql, $values, 30); # 10

#	( $result ) = Para::Frame::Worker->method('RDF::Base::Search', 'get_result', $sql, $values, 30, $maxlimit); # 10

#	debug "fast search - done";
    }

    $args->{'materializer'} ||= \&RDF::Base::List::materialize;
    $args->{'limit_display'} ||= $search->{'limit_display'};


    if( $search->{'query'}{'arc'} )
    {
	$search->{'result'} = RDF::Base::Arc::List->new($result, $args);
    }
    else
    {
	$search->{'result'} = RDF::Base::List->new($result, $args);
    }

    if( debug > 1 )
    {
        my $count = $search->{'result'}->size;
        debug "Got $count matches";
    }


    # Filter out arcs?
    if( my $uap = $args->{unique_arcs_prio} )
    {
	if( $search->{'query'}{'arc'} )
	{
	    $search->{'result'} =
	      $search->{'result'}->unique_arcs_prio($uap);
	}
    }
    elsif( my $aod = $args->{arc_active_on_date} )
    {
	if( $search->{'query'}{'arc'} )
	{
	    $search->{'result'} =
	      $search->{'result'}->arc_active_on_date($aod);
	}
    }

    if( my $filter = $search->{'filter'} )
    {
        debug "Applying filter ".query_desig($filter);
        my $result = $search->{'result'}->find($filter);
        $search->{'result'} = $result;
        debug "Filter applied";
    }


    if( debug > 3 )
    {
        debug("Got result ".datadump($search->{'result'}));
    }

    return '';
}


##############################################################################

sub get_result
{
    my( $this, $sql, $values, $timeout, $maxlimit ) = @_;

    my( $class,  $search );

    if( ref $this )
    {
	$search = $this;
	$class = ref $this;
	$maxlimit ||= $search->{'maxlimit'};
    }
    else
    {
	$class = $this;
    }


    my $dbh = $RDF::dbix->dbh;


#    if( utf8::is_utf8($sql) )
#    {
#	if( utf8::valid($_) )
#	{
#	    debug "SQL is valid UTF8";
#	}
#	else
#	{
#	    debug "SQL is INVALID UTF8";
#	}
#    }
#    else
#    {
#	debug "SQL is NOT UTF8";
#    }


#    my $sth = $dbh->prepare_cached( $sql );
    my $sth = $dbh->prepare( $sql );

#    $timeout ||= 20;
    $timeout ||= 30;

    my $time = time;
    eval
    {
	$dbh->do(sprintf "set statement_timeout = %d", $timeout*1000);
#	warn "Executing stmt at $time\n";
	$sth->execute(@$values);
#	warn sprintf "Done at           %s\n",time;

	$dbh->do("set statement_timeout = 0000");
    };
    if( $@ )
    {
	if( $RDF::dbix->state->is('query_canceled') )
	{
	    debug "Database search took to long";
	    debug $@;
	    debug sprintf "Took %.2f seconds", (time - $time);
	    if( $search )
	    {
		debug $search->sysdesig;
		debug $search->sql_sysdesig;
	    }
	    throw('dbi', "Database search took to long");
	}

	cluck "DB error at";
	throw('dbi',  $@ . "Values: ".join(", ", map{defined $_ ? "'$_'" : '<undef>'} @$values)."\n");
    }

    if( $search and (debug > 3) )
    {
	my $took = time - $time;
	debug(sprintf("Execute: %2.2f", $took));
	debug $search->sysdesig;
	debug $search->sql_sysdesig;
    }

    my( @result, %found );
    while( my( $subj_id, $score ) = $sth->fetchrow_array )
    {
	# We save execution time by not eliminating all duplicates
	if( $found{ $subj_id } ++ )
	{
	    # Duplicate found. Subtract number of hits
	    next;
	}

	push @result, $subj_id;
	if( $maxlimit )
	{
	    last if $#result >= $maxlimit -1;
	}
    }
    $sth->finish;

#    debug sprintf "Got %d hit", scalar(@result);
#    debug datadump(\@result); ### DEBUG

    return \@result;
}


##############################################################################

sub build_sql
{
    my( $search ) = @_;

    if( my $sql = $search->{'sql_string'} )
    {
	my $values = $search->{'sql_values'};
	my $min_prio = $search->{'min_prio'} || 0;
	return( $sql, $values, $min_prio );
    }

    my @elements;

    # paths
    if( my $paths = $search->{'query'}{'path'} )
    {
	push @elements, @{ $search->elements_path( $paths ) };
    }

    # nodes
    if( my $nodes = $search->{'query'}{'node'} )
    {
	push @elements, @{ $search->elements_nodes( $nodes ) };
    }

    # props
    if( my $props = $search->{'query'}{'prop'} )
    {
	push @elements, @{ $search->elements_props( $props ) };
    }

    # arcs
    if( my $qarc = $search->{'query'}{'arc'} )
    {
	push @elements, @{ $search->elements_arc( $qarc ) };
    }

    unless( @elements ) # Handle empty searches
    {
	debug( 2, "*** Empty search");
	$search->{'result'} = RDF::Base::List->new_empty();
	return();
    }

    my @outer_score = ();
    my @main_select = ();
    my @main_where  = ();
    my @outer_where = ();
    my @outer_order = ();

    foreach my $element ( sort { $a->{'prio'} <=> $b->{'prio'} } @elements )
    {
	if( my $scores = $element->{'score'} )
	{
	    foreach my $part (@$scores)
	    {
		my $name = $part->{'name'};
		push @outer_score, $name;
		push @main_select, $part;
	    }
	    push @outer_where, $element;
	}
	else
	{
	    push @main_where, $element;
	}
    }

    my $min_prio = $main_where[0]->{'prio'} || 0;

    if( debug > 3 )
    {
	my $report = "";
	$report .= "MAIN WHERE  ".datadump(\@main_where);
	$report .= "MAIN SELECT ".datadump(\@main_select);
	$report .= "OUTER WHERE ".datadump(\@outer_where);
	$report .= "OUTER SCORE ".datadump(\@outer_score);
	debug $report;
    }


    my( $select_sql, $select_values, $sortkeys ) =
	$search->build_outer_select( \@outer_score );
    my( $main_sql,   $main_values   ) = $search->build_main( \@main_select, \@main_where );
    my( $where_sql,  $where_values  ) = build_outer_where( \@outer_where );
    my( $order_sql,  $order_values  ) = $search->build_outer_order( $sortkeys );

    # Clean values

    my @values = map{ ref $_ ? $_->plain : $_ } (
						 @$select_values,
						 @$main_values,
						 @$where_values,
						 @$order_values,
						);
    # Upgrade to UTF8
    foreach( @values )
    {
	utf8::upgrade($_);
    }

    my $sql = "select $select_sql from ( $main_sql ) as frame";
    if( $where_sql )
    {
	$sql .= " where $where_sql";
    }
    if( $order_sql )
    {
	$sql .= " order by $order_sql";
    }

    if( my $limit = $search->{'maxlimit'} )
    {
	if( BINDVALS )
	{
	    $sql .= " limit ?";
	    push @values, $limit;
	}
	else
	{
	    my $dbh = $RDF::dbix->dbh;
	    $sql .= sprintf " limit %s", $dbh->quote($limit);
	}
    }


    my $values = \@values; # Lock ref
    $search->{'sql_string'} = $sql;
    $search->{'sql_values'} = $values;
    $search->{'min_prio'} = $min_prio;

    return( $sql, $values, $min_prio );
}

sub sql_string
{
    return $_[0]->{'sql_string'} || "";
}

sub sql_values
{
    return $_[0]->{'sql_values'} || [];
}

sub reset_sql
{
    $_[0]->{'sql_string'} = undef;
    $_[0]->{'sql_values'} = undef;
}


##############################################################################

=head2 node

Get the search object in node form

=cut

sub node
{
    my( $search ) = @_;

    die "FIXME: C_search";

    my $node = $search->{'node'};

    unless( $node )
    {
	$node = RDF::Base::Resource->create({is=>'search'});

	foreach my $prop ( values %{$search->{'query'}{'prop'}} )
	{
	    my $preds = $prop->{'pred'};
	    unless( UNIVERSAL::isa( $preds, 'Para::Frame::List' ) )
	    {
		$preds = RDF::Base::List->new([$prop->{'pred'}]);
	    }

	    foreach my $pred ( $preds->as_array )
	    {
		my $values = $prop->{'values'};

		$node->add({ $pred->plain => $values });
	    }
	}
    }

    return $search->{'node'} = $node;
}


#########################################################################
################################  Private methods  ######################

sub remove_node
{
    my( $search ) = @_;

    if( my $node = $search->{'node'} )
    {
	# Ignore node if it's not in the cache
	# It may already be gone
	if( $RDF::Base::Cache::Resource{ $node->id } )
	{
	    $node->remove;
	}

	delete $search->{'node'};
    }
}



##############################################################################

sub add_prop
{
    my( $search, $rec ) = @_;

    ## pred is always an object here, I guess
    my $preds = $rec->{'pred'};



    my $pred_key = join ',', map $_->id, $preds->as_array;
    my $rev = $rec->{'rev'}||'';
    my $match = $rec->{'match'}||'';
    my $key = join('-', $pred_key, $rev, $match);
    $key .= '='.join '+', map{ref $_ ? $_->syskey : RDF::Base::Literal::String->new($_)->syskey} @{$rec->{'values'}};

    $rec->{'key'} = $key;
    my $pred_name = "";
    if( $preds->size == 1 )
    {
	my $first = $preds->get_first_nos;
	$pred_name = $first->plain;
	$search->replace( 'prop', $pred_name  );
	$search->replace( 'props', $pred_name );
    }
    else
    {
	## This shold be a list of pred objs

	# TODO: Check $search->replace, et al
    }

    $search->{'query'}{'prop'}{$key} = $rec;

    $search->reset_sql;
}


##############################################################################

sub replace
{
    my( $search, $type, $target ) = @_;

    my $req = $Para::Frame::REQ;

    ### Replace old values if asked for and not already done
    if ( $req and $req->is_from_client )
    {
	my $q = $req->q;
#	debug "DO replace?\n";
	my @replace_target = ();
	foreach my $replace ( $q->param('replace') )
	{
#	    debug "  check $replace with ".$rec->{'pred'}->name."\n";
	    my( $ctype, $ctarget ) = split(/_/, $replace, 2 );
	    if( $type eq $ctype and $target eq $ctarget )
	    {
		$search->broaden( $type, $target );
	    }
	    else
	    {
		push @replace_target, $replace;
	    }
	}
	$q->param('replace', @replace_target);
    }

    $search->reset_sql;
}


##############################################################################

sub rev_query
{
    my( $search, $full ) = @_;
    #
    # Revert search obj to a set of name/value pairs
    #
    # give all variants if $full is true

    my $props = {};

    foreach my $cc ( keys %{$search->{'query'}} ) # cc = criterion class
    {
	if( $cc eq 'path' )
	{
	    foreach my $path ( keys %{$search->{'query'}{'path'}} )
	    {
		my $values = $search->{'query'}{'path'}{$path};
		my $val = $values->[0]; # Limited support
		$props->{"path_${path}"} = $val;
	    }
	}
	elsif( $cc eq 'order_by' )
	{
	    # Limited support
	    if( my $order = $search->{'query'}{'order_by'}[0] )
	    {
		$props->{"order_by"} = $order;
	    }
	}
	elsif( $cc eq 'prop' )
	{
	    foreach my $prop ( values %{$search->{'query'}{'prop'}} )
	    {
		my $rev = $prop->{'rev'};
		my $preds = $prop->{'pred'};
		my $pred_alt; # Alternative pred part
		my $type = $prop->{'type'};
		my $match = $prop->{'match'} ||= 'eq';
		my $values = $prop->{'values'};
#		my $val = $values->[0]; # Limited support
		my $prio = $prop->{'prio'};
		my $clean = $prop->{'clean'};

#		debug "VALUES: @$values";

		foreach my $val ( @$values )
		{
		    if( ref $val and UNIVERSAL::isa( $val, 'RDF::Base::Resource') )
		    {
			$val = $val->desig;  # Changes val i array
		    }
		}

		my $pred;
		if( $preds->size > 1 )
		{
		    my @pred_names = map $_->name, $preds->as_array;
		    $pred_alt = 'predor_'.join('_-_', $preds->as_array) if $full;
		    $pred = 'predor_'.join('_-_', @pred_names);
		}
		else
		{
		    $pred = $preds->get_first_nos;
		    $pred_alt = $pred->plain;
		    $pred_alt = undef if $pred eq $pred_alt;
		}

		if( not $full )
		{
		    $pred = undef if $pred_alt;
		}

		foreach my $p ( $pred, $pred_alt )
		{
		    next unless $p;

		    my @alts; # alternative ways to specify criterion

		    my $str = "";
		    if( $rev )
		    {
			if( $full )
			{
			    $str .= 'revprop_';
			}
			else
			{
			    $str .= 'rev_';
			}
		    }
		    elsif( $full )
		    {
			$str .= 'prop_';
		    }

		    if( ref $p and UNIVERSAL::isa( $p, 'RDF::Base::Resource') )
		    {
			$str .= $p->name;
		    }
		    else
		    {
			$str .= $p;
		    }

		    if( $clean )
		    {
			$str .= '_clean';
		    }

		    if( $match eq 'eq' )
		    {
			push @alts, [$str, $values];
		    }

		    $str .=  '_'. $match;

		    push @alts, [$str, $values];

		    if( $prio )
		    {
			$str .= '_'. $prio;
			push @alts, [$str, $values];
		    }

#		    debug "VALUES @$values\n";

		    if( $full )
		    {
			foreach my $pair ( @alts )
			{
			    push @{ $props->{$pair->[0]}}, @{$pair->[1]};
			}
		    }
		    else
		    {
			push @{ $props->{$alts[0][0]}}, @{$alts[0][1]};
		    }
		}
	    }
	}
    }
    return $props;
}


##############################################################################

=head2 criterions

Transform search to set of PUBLIC explained criterions.

props:	push( @{$ecrits->{$pred_name}{'prop'}}, $prop );

$pred_name is in a form equal to the one used in html forms

$prop is the value node

=cut

sub criterions
{
    my( $search, $args ) = @_;

    debug "Getting criterions";

    $args ||= {};

    my $ecrits = {};

    foreach my $cc ( keys %{$search->{'query'}} ) # cc = criterion class
    {
	if( $cc eq 'path' )
	{
	    foreach my $path ( keys %{$search->{'query'}{'path'}} )
	    {
		my $values = $search->{'query'}{'path'}{$path};
		debug "not implemented";
	    }
	}
	elsif( $cc eq 'prop' )
	{
	    foreach my $prop ( values %{$search->{'query'}{'prop'}} )
	    {
#		debug "Considering $prop";
		# Do not include private parts, since criterions is
		# for public presentation
		unless( $args->{'private'} )
		{
		    next if $prop->{'private'};
		}

		my $rev = $prop->{'rev'};
		my $preds = $prop->{'pred'};
#		my $type = $prop->{'type'};
#		my $match = $prop->{'match'};
#		my $values = $prop->{'values'};
#		my $val = $values->[0]; # Limited support
#		my $prio = $prop->{'prio'};


		my $pred_name;
		if( $preds->size > 1 )
		{
		    if( ! $preds->get_first_nos )
		    {
			cluck datadump $prop;
			return undef; # Safe fallback
		    }
		    ### CHECK ME
#			die "not implemented";
		    my $ors = join '_-_', map $_->plain, $preds->as_array;
		    $pred_name = "predor_$ors";
		}
		else
		{
		    $pred_name = $preds->get_first_nos->plain;
		}


		if( $rev )
		{
		    $pred_name = "rev$pred_name";
		}

#		debug "  pred $pred_name";
		push( @{$ecrits->{$pred_name}{'prop'}}, $prop );
	    }
	}
    }

    if( keys %$ecrits )
    {
#	debug "Returning criterions ".datadump($ecrits,2);
	return $ecrits;
    }
    else
    {
	debug 3, "  No criterions found";
	return undef;
    }
}


##############################################################################

sub criterion_to_key
{
    my( $search, $cond ) = @_;

    my $rev = $cond->{'rev'};
    my $preds = $cond->{'pred'};
    my $match = $cond->{'match'};
    my $arclim = $cond->{'arclim'};
    my $clean = $cond->{'clean'};

    my $prio = $cond->{'prio'} ||= set_prio( $cond );

    my $pred_name;
    if( $preds->size > 1 )
    {
	my $ors = join '_-_', map $_->plain, $preds->as_array;
	$pred_name = "predor_$ors";
    }
    else
    {
	$pred_name = $preds->get_first_nos->plain;
    }

    if( $rev )
    {
	$pred_name = "rev$pred_name";
    }

    if( $arclim )
    {
	$pred_name .= "_$arclim";
    }

    if( $clean )
    {
	$pred_name .= "_$clean";
    }

    if( $match )
    {
	$pred_name .= "_$match";
    }

    if( $prio )
    {
	$pred_name .= "_$prio";
    }

    return $pred_name;
}



##############################################################################

sub build_outer_order
{
    my( $search, $sortkeys ) = @_;

    my $sql = join ", ", @$sortkeys;
    my @values = ();

    return( $sql, \@values );
}


##############################################################################

sub build_outer_where
{
    my( $parts ) = @_;

    my @values = ();
    my @where_sql = ();
    foreach my $part ( @$parts )
    {
	my @where = ref $part->{'where'} ? @{$part->{'where'}} : $part->{'where'};
	push @where_sql, join " and ", map "( $_ )", @where;
	push @values, @{$part->{'values'}};
    }

    my $sql = join " and ", @where_sql;

    return( $sql, \@values );
}


##############################################################################

sub build_outer_select
{
    my( $search, $scores ) = @_;

    my @parts = ();
    my @values = ();
    my @sortkeys = ();

    push @parts, 'node as subj';

    if( $search->{'query'}{'sorttype'}{'score'} )
    {
	my( $score_sql, $score_values ) =  build_outer_select_score( $scores );
	push @parts, $score_sql;
	push @values, @$score_values;
    }

    foreach my $sort ( @{$search->{'query'}{'order_by'}} )
    {
	# Special cases
	if( $sort =~ /^(score|random)\b/ )
	{
	    push @sortkeys, $sort;
	    next;
	}

	my( $field_part, $field_values, $sortkey ) =
	    $search->build_outer_select_field($sort);
	push @parts, $field_part;
	push @values, @$field_values;
	push @sortkeys, $sortkey;
    }

    my $sql = join(", ", @parts);

    return( $sql, \@values, \@sortkeys );
}


##############################################################################

sub build_outer_select_score
{
    my( $scores ) = @_;

    my @part_sql = ();
    my @values = ();

    foreach my $name ( @$scores, 'price' )
    {
	push @part_sql, "coalesce($name, 0)";
    }

    my $sql = join " + ", @part_sql;
    $sql = "( $sql ) as score";

    return( $sql, \@values );
}


##############################################################################

sub build_main
{
    my( $search, $elems_select, $elems_where ) = @_;

    my( @main_from ) = shift @$elems_where;

    # Selected limit. Weighted for optimal result
    my $limit = min( ($main_from[0]->{'prio'} + 1), 5 );

    # Add the best parts in intersection

    while( @$elems_where and $elems_where->[0]->{'prio'} <= $limit )
    {
	push @main_from, shift @$elems_where;
    }

    my( $sql_select, $values_select ) = $search->build_main_select( $elems_select );
    my( $sql_from,   $values_from   ) = build_main_from( \@main_from );
    my( $sql_where,  $values_where  ) = build_main_where( $elems_where );

#    debug "2--> $values_select, $values_from, $values_where\n";
    my @values = ( @$values_select, @$values_from, @$values_where );

    my $sql = "select $sql_select from $sql_from";
    if( $sql_where )
    {
	$sql .= " where $sql_where";
    }

    return( $sql, \@values );
}


##############################################################################

sub build_main_where
{
    my( $elements ) = @_;

    my @values = ();
    my @parts = ();

    foreach my $part ( @$elements )
    {
	my $select = $part->{'select'} or die "select missing";
	$select eq '1'               and die "malformed select";

	my @where = ref $part->{'where'} ? @{$part->{'where'}} : $part->{'where'};
	my $table = $part->{'table'} || 'arc';

	my $part_sql = join " UNION ", map "select 1 from $table where $select=main.node and $_", @where;

	my $sql;
	if( $part->{'negate'} )
	{
	    $sql = "not exists ( $part_sql )";
	}
	else
	{
	    $sql = "exists ( $part_sql )";
	}

	push @parts, $sql;
	push @values, @{$part->{'values'}};
    }

    my $sql = join " and ", @parts;

    return( $sql, \@values );
}


##############################################################################

sub build_main_from
{
    my( $parts ) = @_;

    my @part_sql_list;
    my @values;

    foreach my $part (@$parts )
    {
	my $part_sql;
	if( my $where = $part->{'where'} )
	{
	    my @where = ref $part->{'where'} ? @{$part->{'where'}} : $part->{'where'};
	    my $table = $part->{'table'} || 'arc';
	    my $select = $part->{'select'};
	    unless( $select eq 'node' )
	    {
		$select .= " as node";
	    }

	    if( $part->{'negate'} )
	    {
		debug "WARNING! VERY BIG SEARCH!";
		$part_sql .= join " INTERSECT ", map "select distinct $select from $table where not($_)", @where;
	    }
	    else
	    {
		# Found a case where this gave a 500 times speed increase
		$part_sql .= join " UNION ", map "select distinct $select from $table where $_", @where;
	    }
	}
	else
	{
	    if( $part->{'negate'} )
	    {
		confess "not implemented: ".datadump($parts);
	    }


	    ### DEBUG
	    unless($part->{'select'})
	    {
		confess datadump( $part );
	    }

	    # TODO:
	    # We save more time in the common case if we only use 'distinct'
	    # in cases it realy cuts down the number of records
	    #
	    $part_sql .= "select distinct $part->{'select'} from arc";
	}

	push @part_sql_list, $part_sql;
	push @values, @{$part->{'values'}};
    }

    my $intersect = join " INTERSECT ", map "($_)", @part_sql_list;


    my $sql    = "( $intersect ) as main";

    return( $sql, \@values );
}


##############################################################################

sub build_main_select
{
    my( $search, $elems_select ) = @_;

    my @parts = ();
    my @values = ();

    push @parts, 'node';

    my( $score_parts, $score_values ) = build_main_select_group($elems_select);
    push @parts, @$score_parts;
    push @values, @$score_values;

    if( $search->{'query'}{'sorttype'}{'score'} )
    {
	push @parts, $search->build_main_select_price();
    }

   my $sql = join(", ", @parts);


    return( $sql, \@values );
}


##############################################################################

sub build_outer_select_field
{
    # NB! No longer sorts result using clean

    my( $search, $field_in ) = @_;

    my $dbh = $RDF::dbix->dbh;
    my $fieldpart = $field_in or confess "Param field missing";

    $fieldpart =~ s/\bdesig$/name.loc/;

    # Keep first part (exclude asc/desc)
    my $dir = 'asc';
    if( $fieldpart =~ s/\s+(.*)$// )
    {
	$dir = $1 || 'asc';
    }

    my $sortkey = $fieldpart;
    $sortkey =~ s/\./_/g;

    $sortkey or croak "sortkey not defined";

    my $sql;
    my @values = ();


    # Used as a field, should only be one value!

#
# Handling our_reference.name:
#
# (select valclean from rel where sub in ( select obj from rel where
# sub=frame.node and pred=116 limit 1) and pred=11 limit 1)
#

#    debug "Building sorting sql from $fieldpart";

    while( $fieldpart )
    {
	my $tr=0;
	my $field = $fieldpart;

	# Split in first part and rest
	if( $fieldpart =~ s/^([^\.]+)\.//)
	{
	    $field = $1;

	    if( $fieldpart eq 'loc' )
	    {
		$tr = 1;
		$fieldpart = "";
	    }
	}
	else
	{
	    $fieldpart = "";
	}

#	debug "  field $field";

	# Should also take dynamic preds like 'is'
	my $pred = RDF::Base::Pred->get( $field );
	my $coltype = $pred->coltype;
	# Sort on real value. Not clean

	my $where = "subj=frame.node";
	if( $sql )
	{
	    $where = "subj in ($sql)";
#	    debug "  Setting where to previous part";
	}

	my $arclim_sql = $search->arclim_sql;

	if( $tr )
	{
	    if( $dir eq 'exists' )
	    {
		confess "Not sane";
	    }
	    my $weight_id = RDF::Base::Resource->get_by_label('weight')->id;

	    # Sort by weight
	    $sql ="select $coltype from (select $coltype, CASE WHEN obj is not null THEN (select valfloat from arc where pred=${weight_id} and subj=${sortkey}_inner.obj $arclim_sql) ELSE 0 END as weight from arc as ${sortkey}_inner where $where and pred=? $arclim_sql order by weight limit 1) as ${sortkey}_mid";
	}
	elsif( $dir eq 'exists' )
	{
	    $sql = "COALESCE((select 1 from arc where $where and pred=? $arclim_sql limit 1),0)";
	}
	elsif( $coltype eq 'valfloat' )
	{
	    $sql = "COALESCE((select $coltype from arc where $where and pred=? $arclim_sql limit 1),0)";
	}
	elsif( $coltype eq 'valtext' )
	{
	    $sql = "COALESCE((select $coltype from arc where $where and pred=? $arclim_sql limit 1),'')";
	}
	else # valdate or obj
	{
	    $sql = "select $coltype from arc where $where and pred=? $arclim_sql limit 1";
	}

	if( BINDVALS )
	{
	    push @values, $pred->id;
	}
	else
	{
	    my $id = $pred->id;
	    $sql =~ s/\?/$id/;
	}
    }

    $sql = "($sql) as $sortkey";

    if( $dir eq 'exists' )
    {
	$dir = 'desc';
    }

#    debug "SORT SQL: $sql";
    return( $sql, \@values, "$sortkey $dir" );
}


##############################################################################

sub build_main_select_group
{
    my( $elems ) = @_;

    my @parts = ();
    my @values = ();
    foreach my $elem ( @$elems )
    {
	### 'Distinct' evades error from dirty DB data
	my $sql = "select distinct $elem->{'select'} ";
	$sql   .= "from arc ";
	$sql   .= "where subj=main.node and ";
	$sql   .= $elem->{'where'};

	$sql = "($sql) as ".$elem->{'name'};

	push @parts, $sql;
	push @values, @{$elem->{'values'}};
    }

    return( \@parts, \@values );
}


##############################################################################

# rel1 is the has_subscription relation and rel2 is the weight
# relation of the specific subscription object.

# TODO: Remove this rg-specific sorting

# pred=1 and obj=1111 => is subscription

sub build_main_select_price
{
    my( $search ) = @_;

    my $arclim_sql0 = $search->arclim_sql();
    my $arclim_sql1 = $search->arclim_sql({prefix => 'rel1.'});
    my $arclim_sql2 = $search->arclim_sql({prefix => 'rel2.'});
    my $weight_id = RDF::Base::Resource->get_by_label('weight')->id;

    my $sql =
"
              (
               select sum(rel2.valfloat)
               from arc as rel1, arc as rel2
               where
                   rel1.subj=main.node and rel1.obj=rel2.subj and rel2.pred=${weight_id} and rel1.indirect is false and
                   exists
                   (
                       select 1
                       from arc
                       where subj=rel2.subj and pred=1 and obj=1111
                             $arclim_sql0
                   )
                   $arclim_sql1
                   $arclim_sql2
               group by rel1.subj
           ) as price
";

    return $sql;
}


##############################################################################

sub elements_nodes
{
    my( $search, $nodes ) = @_;

    my @element;

    foreach my $snode ( @$nodes )
    {
	my $pred_name = $snode->{'pred_name'};
	my $prio_override = $snode->{'prio'};
	my $match = $snode->{'match'} || 'eq';
	my $negate = ( $match eq 'ne' ? 1 : 0 );
	my $invalues = $snode->{'values'};

	my @outvalues;
	my $where;

	my $prio = 3;
	if( $pred_name eq 'label' )
	{
	    $prio = 1;
	}

	if( $match eq 'exist' )        # match any
	{
	    $where = "($pred_name is not null)";
	    $prio += 2;

	    if( $invalues->[0] == 0 ) # NOT exist
	    {
		$negate = 1;
		$prio += 5;
	    }
	}
	elsif( $pred_name eq 'id' )
	{
	    if( BINDVALS )
	    {
		$where = join(" or ", map "node = ?", @$invalues);
		@outvalues = @$invalues; # value should be numeric
	    }
	    else
	    {
		$where = join(" or ", map "node = $_", @$invalues);
	    }
	    $prio = 1;
	}
	else
	{
	    my $matchpart = matchpart( $match );

	    unless( $match eq 'eq' )
	    {
		$prio += 4;
	    }

	    if( BINDVALS )
	    {
		$where = join " or ", map "($pred_name $matchpart ?)", @$invalues;
		push @outvalues, @$invalues;
	    }
	    else
	    {
		my $dbh = $RDF::dbix->dbh;
		$where = join " or ", map sprintf("($pred_name $matchpart %s)", $dbh->quote($_)), @$invalues;
	    }
	}

	push @element,
	{
	 select => 'node', # TODO: Also implement id select
	 where => $where,
	 values => \@outvalues,
	 prio => ($prio_override || $prio),
	 table => 'node',
	 negate => $negate,
	};
    }

    return( \@element );
}


##############################################################################

sub elements_arc
{
    my( $search, $qarc ) = @_;

    my @element;
    my $prio = 10;
    my $dbh = $RDF::dbix->dbh;

    my @values;
    my @parts;

    my $arclim = $qarc->{'arclim'} || $search->arclim;
    my $args = {};

    if( BINDVALS )
    {
	if( my $vals = $qarc->{'id'} )
	{
	    my $part = join " or ", map "(ver=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = 1;
	}

	if( my $vals = $qarc->{'subj'} )
	{
	    my $part = join " or ", map "(subj=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = min( $prio, 3 );
	}

	if( my $vals = $qarc->{'pred'} )
	{
	    my $part = join " or ", map "(pred=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	}

	if( my $vals = $qarc->{'created_by'} )
	{
	    my $part = join " or ", map "(created_by=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = min( $prio, 5 );
	}

	if( my $vals = $qarc->{'updated_by'} )
	{
	    my $part = join " or ", map "(updated_by=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = min( $prio, 5 );
	}

	if( my $vals = $qarc->{'created'} )
	{
	    my $part = join " or ", map "(created=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = min( $prio, 7 );
	}

	if( my $vals = $qarc->{'updated'} )
	{
	    my $part = join " or ", map "(updated=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = min( $prio, 7 );
	}

	if( my $vals = $qarc->{'arc_weight'} )
	{
	    my $part = join " or ", map "(weight=?)", @$vals;
	    push @parts, "($part)";
	    push @values, @$vals;
	    $prio = min( $prio, 8 );
	}

	if( my $coltype = $qarc->{'coltype'} )
	{
	    my $vals = $qarc->{$coltype};
	    my $part = join " or ", map "($coltype=?)", @$vals;
	    if( $part )
	    {
		push @parts, "($part)";
		push @values, @$vals;
		if( $coltype eq 'obj' )
		{
		    $prio = min( $prio, 4 );
		}
	    }
	}
    }
    else
    {
	if( my $vals = $qarc->{'id'} )
	{
	    my $part = join " or ", map sprintf("(ver=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = 1;
	}

	if( my $vals = $qarc->{'subj'} )
	{
	    my $part = join " or ", map sprintf("(subj=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = min( $prio, 3 );
	}

	if( my $vals = $qarc->{'pred'} )
	{
	    my $part = join " or ", map sprintf("(pred=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	}

	if( my $vals = $qarc->{'created_by'} )
	{
	    my $part = join " or ", map sprintf("(created_by=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = min( $prio, 5 );
	}

	if( my $vals = $qarc->{'updated_by'} )
	{
	    my $part = join " or ", map sprintf("(updated_by=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = min( $prio, 5 );
	}

	if( my $vals = $qarc->{'created'} )
	{
	    my $part = join " or ", map sprintf("(created=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = min( $prio, 7 );
	}

	if( my $vals = $qarc->{'updated'} )
	{
	    my $part = join " or ", map sprintf("(updated=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = min( $prio, 7 );
	}

	if( my $vals = $qarc->{'arc_weight'} )
	{
	    my $part = join " or ", map sprintf("(weight=%s)",$dbh->quote($_)), @$vals;
	    push @parts, "($part)";
	    $prio = min( $prio, 8 );
	}

	if( my $coltype = $qarc->{'coltype'} )
	{
	    my $vals = $qarc->{$coltype};
	    my $part = join " or ", map sprintf("($coltype=%s)",$dbh->quote($_)), @$vals;
	    if( $part )
	    {
		push @parts, "($part)";
		if( $coltype eq 'obj' )
		{
		    $prio = min( $prio, 4 );
		}
	    }
	}
    }

    my $where = join " and ", @parts;
    if( length $where )
    {
	my $arclim_sql = $arclim->sql($args);
	if( $arclim_sql )
	{
	    $where .= " and " . $arclim_sql;
	    $prio = min($prio, $arclim->sql_prio($args));
	}
    }
    else
    {
	$where = $arclim->sql($args);
	$prio = min($prio, $arclim->sql_prio($args));
    }

    push @element,
    {
     select => 'ver', # TODO: Also implement id select
     where => $where,
     values => \@values,
     prio => $prio,
    };

    return( \@element );
}


##############################################################################

sub elements_path
{
    my( $search, $paths ) = @_;

    my @element;
    foreach my $path ( keys %$paths )
    {
	my( $where, $path_values, $prio ) = $search->build_path_part( $paths->{$path} );

	push @element,
	{
	    select => 'subj',
	    where => $where,
	    values => $path_values,
	    prio => $prio,
	};
    }

    return( \@element );
}


##############################################################################

sub elements_props
{
    my( $search, $props ) = @_;

    my $dbh = $RDF::dbix->dbh;

    my @element;
    foreach my $cond ( values %$props )
    {
	my $rev = $cond->{'rev'};
	my $preds = $cond->{'pred'}; # The obj or obj list
	my $type = $cond->{'type'};
	my $match = $cond->{'match'} ||= 'eq';
	my $invalues = $cond->{'values'};
	my $prio = $cond->{'prio'};
	my $arclim = $cond->{'arclim'} || $search->arclim;

	my $negate = ( $match eq 'ne' ? 1 : 0 );

	unless( $prio )
	{
	    $prio = set_prio( $cond );
	}

	my $arclim_sql = $search->arclim_sql({ arclim => $arclim });

	my $select = ($rev ? 'obj' : 'subj');
	my $where;
	my @outvalues;

	my $pred_part;
	my @pred_ids;
	if( $preds->size > 1 )
	{
	    my( @parts );
	    foreach my $pred ( $preds->as_array )
	    {
#		debug( 2, sprintf "Prio for %s is $prio", $pred->desig);

		if( $pred->plain eq 'id' )
		{
		    die "not implemented";
		}
		else
		{
		    if( BINDVALS )
		    {
			push @parts, "pred=?";
			push @pred_ids, $pred->id;
		    }
		    else
		    {
			push @parts, "pred=".$pred->id;
		    }
		}
	    }
	    $pred_part = "(".join(" or ", @parts).")";
	}
	else
	{
#	    debug( 2, sprintf "Prio for %s is $prio", $pred->desig);

	    if( BINDVALS )
	    {
		@pred_ids = $preds->get_first_nos->id;
		$pred_part = "pred=?";
	    }
	    else
	    {
		$pred_part = "pred=".$preds->get_first_nos->id;
	    }
	}


	if( $match eq 'exist' )        # match any
	{
	    $where = "$pred_part $arclim_sql";
	    @outvalues = @pred_ids;
	    if( $invalues->[0] == 0 ) # NOT exist
	    {
		$negate = 1;
	    }
	}
	elsif( ($preds->size < 2) and
	       ($preds->get_first_nos->plain eq 'id') )
	{
	    if( BINDVALS )
	    {
		$where = join(" or ", map "subj = ?", @$invalues);
		@outvalues = @$invalues; # value should be numeric
	    }
	    else
	    {
		$where = join(" or ", map "subj = $_", @$invalues);
	    }
	    $where .= " " . $arclim_sql;
	    $prio = 1;
	}
	else
	{
	    confess "In elements_props: ".datadump $cond unless $type; ### DEBUG

	    my $matchpart = matchpart( $match );
	    my @matchvalues;
	    if( BINDVALS )
	    {
		$matchpart = join(" or ", map "$type $matchpart ?", @$invalues);
		@matchvalues =  @{ searchvals($cond) };
	    }
	    else
	    {
		$matchpart = join(" or ", map "$type $matchpart ".$dbh->quote($_), @{ searchvals($cond) });
	    }

	    $where = "$pred_part and ($matchpart) $arclim_sql";
	    @outvalues = ( @pred_ids, @matchvalues);
	}

	if( $search->add_stats )
	{
#	    debug sprintf("--> add stats for props search? (type $type, pred %s, vals %s)\n",
#			 $pred->name, join '-', map $_, @$invalues);
	    if( $type =~ /^(obj|subj|id)$/ )
	    {
		foreach my $node_id ( @$invalues )
		{
		    RDF::Base::Resource->get($node_id)->log_search;
		}
	    }
	}


	$prio = 10 if $match eq 'ne';

	push @element,
	{
	    where => $where,
	    select => $select,
	    values => \@outvalues,
	    prio => $prio,
	    negate => $negate,
	};
    }

    return \@element;
}


##############################################################################

sub build_path_part
{
    my( $search, $path_rec ) = @_;

    # Hmm... Documentation - Lets think...  Example: ( path _
    # in_region __ name = sweden ) last part (name) is the type we
    # look for, those value should be "sweden".  The intermidiary
    # parts should be preds to objs.  A larger path would be
    # path_parent__brother__employer__organisation_id = 12345.  This
    # should find all things (persons) those parents that has a
    # brother that is employed by an organisation with id 12345.

    # The plan is to resolve the path to a list of possible values and
    # insert those alternatives directly in the bigger search query in
    # which this path is just one part. This resulting list uses the
    # first part of the path. Since first and last step is specially
    # handled, we assume we have at least two steps.

    # Addition: A step of the form predor_in_region_-_near_region says
    # that we have two alternatives for the pred for that step. Just
    # OR them together.

    my $dbh = $RDF::dbix->dbh;
    my $path = $path_rec->{'path'};
    my $values = $path_rec->{'values'};
    my $clean = $path_rec->{'clean'};

    my( @steps ) = split /__/, $path;

    my $last_step = pop @steps;
    my $first_step = shift @steps;

    my $arclim_sql = $search->arclim_sql;

    #### LAST STEP

    my $pred = RDF::Base::Pred->get( $last_step );
    my $coltype = $pred->coltype;

    if( $clean and ($coltype eq 'valtext') )
    {
	$coltype = 'valclean';
	my @cleanvals;
	foreach my $val ( @$values )
	{
	    push @cleanvals, valclean( \$val );
	}
	$values = \@cleanvals;
    }

    my $where;
    my @path_values;

    if( BINDVALS )
    {
	my $value_part = join " or ", map "$coltype=?", @$values;
	$where = "pred=? and ($value_part) $arclim_sql";
	@path_values = $pred->id;
	push @path_values, @$values;
    }
    else
    {
	my $value_part = join " or ", map "$coltype= ".$dbh->quote($_), @$values;
	my $pred_id = $pred->id;
	$where = "pred=$pred_id and ($value_part) $arclim_sql";
    }


    #### MIDDLE STEPS

    foreach my $step ( reverse @steps )
    {
	my $pred_id = RDF::Base::Pred->get_id($step);

	if( BINDVALS )
	{
	    $where = "pred=? and obj in (select subj from arc where $where) $arclim_sql";
	    unshift @path_values, $pred_id;
	}
	else
	{
	    $where = "pred=$pred_id and obj in (select subj from arc where $where) $arclim_sql";
	}
    }

    my $sql = "select subj from arc where $where";

#    my $time = time;
    my $result = $RDF::dbix->select_list( $sql, @path_values );
#    my $took = time - $time;
#    debug sprintf("Try path list: %2.2f\n", $took);


    #### FIRST STEP

    my $pred_part;
    my @pred_ids;
    if( $first_step =~ s/^predor_// )
    {
	my( @preds ) = split /_-_/, $first_step;
	( @pred_ids ) = map RDF::Base::Pred->get_id($_), @preds;

	if( BINDVALS )
	{
	    $pred_part = join " or ", map "pred=?", @pred_ids;
	    unshift @path_values, @pred_ids;
	}
	else
	{
	    $pred_part = join " or ", map "pred=$_", @pred_ids;
	}

	$pred_part = "($pred_part)";
    }
    else
    {
	( @pred_ids ) = RDF::Base::Pred->get_id($first_step);
	if( BINDVALS )
	{
	    $pred_part = "pred=?";
	    unshift @path_values, @pred_ids;
	}
	else
	{
	    $pred_part = "pred=".$pred_ids[0];
	}
    }

    if( $search->add_stats )
    {
	foreach my $rec ( @$result )
	{
	    RDF::Base::Resource->get($rec->{'subj'})->log_search;
	}
    }

    if( @$result > 1 )
    {
	$where = "$pred_part and obj in( $sql )";
	return( $where, \@path_values, 7);
    }
    elsif( @$result )
    {
	my $value = $result->[0]->{'subj'};
	if( BINDVALS )
	{
	    return( "$pred_part and obj=?", [@pred_ids, $value], 2);
	}
	else
	{
	    return( "$pred_part and obj=$value", [], 2);
	}
    }
    else
    {
	### NOT FOUND

	if( $#$values )
	{
	    my $last = pop @$values;
	    my $str = join ", ", @$values;
	    $str .= " eller $last";
	    $search->broaden('path', $path);
	    throw('notfound', "Hittar varken $str.");
	}
	else
	{
	    $search->broaden('path', $path);
	    throw('notfound', "Hittar inte $values->[0].");
	}
    }
}


##############################################################################

sub set_prio
{
    my( $cond ) = @_;

    my $preds = $cond->{'pred'} or confess "no preds";
    my $first_pred = $preds->get_first_nos;
    my $vals = $cond->{'values'};
    my $match = $cond->{'match'};

    my( $key, $prio, $cnt, $coltype );

    if( ($match ne 'eq') and ($match ne 'exact') )
    {
	if( $match eq 'ne' )
	{
	    return 9;
	}
	elsif( $match eq 'like' )
	{
	    return 5;
	}
	elsif( $match eq 'exist' )
	{
	    if( $vals->[0] )
	    {
		$prio = 2;
	    }
	    else
	    {
		return 9;
	    }
	}
	else
	{
	    return 7;
	}
    }
    elsif( scalar(@$vals) > 5 )
    {
	return 8;
    }
    else
    {
	$prio = 1;
    }

    if( $preds->size > 1 ) #alternative preds
    {
	$key = join('-', map $_->plain, $preds->as_array);
	if( $key eq 'name-name_short-code' ){ return 3 }

	$key .= '='.join ',', @$vals;
	return $DBSTAT{$key} if defined $DBSTAT{$key};

	$coltype = $first_pred->coltype();
	my @predid = map $_->id, $preds->as_array;
	my( $sqlor, $valor, @values );
	if( BINDVALS )
	{
	    $sqlor = join " or ", map "pred=?", @predid;
	    $valor = join " or ", map "$coltype=?", @$vals;
	    @values = (@predid, @$vals);
	}
	else
	{
	    my $dbh = $RDF::dbix->dbh;
	    $sqlor = join " or ", map "pred=$_", @predid;
	    $valor = join " or ", map "$coltype = ".$dbh->quote($_), @$vals;
	}

	my $sql = "select count(subj) from arc where ($sqlor)";
	if( $valor )
	{
	    $sql .= " and ($valor)";
	}
	my $sth = $RDF::dbix->dbh->prepare( $sql );

	eval
	{
	    $sth->execute(@values);
	};
	if( $@ )
	{
	    throw('dbi',  $@ . "Values: ".join(", ", map{defined $_ ? "'$_'" : '<undef>'} @values)."\n");
	}
	($cnt) = $sth->fetchrow_array;
	$sth->finish;
	$prio += 1;
    }
    else
    {
	if( $first_pred->plain eq 'id'       ){ return  1 }
	if( $first_pred->plain eq 'value'    ){ return 10 }
	if( $first_pred->plain eq 'name'     ){ return  2 }
	$coltype = $first_pred->coltype();
	if( $coltype eq 'valtext'      ){ return  3 }

	$key = $first_pred->plain;

	my @svals = @$vals;
	if( $match eq 'exist' )
	{
	    pop @svals;
	}

	$key .= '='.join ',', @svals;
	return $DBSTAT{$key} if defined $DBSTAT{$key};

	my( $sql, $valor, @values );
	if( BINDVALS )
	{
	    $valor = join " or ", map "$coltype=?", @svals;
	    $sql = "select count(subj) from arc where (pred=?)";
	    @values = ($first_pred->id, @svals);
	}
	else
	{
	    my $dbh = $RDF::dbix->dbh;
	    my $pred_id = $first_pred->id;
	    $valor = join " or ", map "$coltype =  ".$dbh->quote($_), @svals;
	    $sql = "select count(subj) from arc where (pred=$pred_id)";
	}

	if( $valor )
	{
	    $sql .= " and ($valor)";
	}

	my $sth = $RDF::dbix->dbh->prepare( $sql );

	eval
	{
	    $sth->execute(@values);
	};
	if( $@ )
	{
	    throw('dbi',  $@ . "Values: ".join(", ", map{defined $_ ? "'$_'" : '<undef>'} @values)."\n");
	}
	($cnt) = $sth->fetchrow_array;
	$sth->finish;
    }

    $prio++ if scalar(@$vals) > 1;

    $prio++ unless $coltype eq 'obj';

    if(    $cnt > 50000 ){ $prio += 6 }
    elsif( $cnt > 10000 ){ $prio += 5 }
    elsif( $cnt >  5000 ){ $prio += 4 }
    elsif( $cnt >  1000 ){ $prio += 3 }
    elsif( $cnt >   500 ){ $prio += 2 }
    elsif( $cnt >   100 ){ $prio += 1 }
    elsif( $cnt >    10 ){ $prio += 0 }
    else                 { $prio -= 1 }

    debug 3, "Setting prio $key = $prio";

    return $DBSTAT{$key} = $prio;
}


##############################################################################

=head2 set_arclim

  $search->set_arclim( $arclim )

See L<RDF::Base::Arc::Lim/limflag>

=cut

sub set_arclim
{
    my( $search, $arclim_in ) = @_;

    my $arclim = RDF::Base::Arc::Lim->parse( $arclim_in );

#    if( (ref $arclim eq 'ARRAY') and ( @$arclim == 0 ) )
#    {
#    debug "Setting arclim to ".$arclim->sysdesig;
#    }

    return $search->{'arclim'} = $arclim;
}


##############################################################################

=head2 arclim

  $search->arclim

See L<RDF::Base::Arc::Lim/limflag>

=cut

sub arclim
{
    return $_[0]->{'arclim'} ||= RDF::Base::Arc::Lim->new;
}


##############################################################################

=head2 set_arc_active_on_date

  $search->set_arclim( $date )

See L<RDF::Base::Arc::List/arc_active_on_date>

=cut

sub set_arc_active_on_date
{
    my( $search, $date ) = @_;

    return $search->{'arc_active_on_date'} =
      $RDF::dbix->format_datetime($date);
}


##############################################################################

=head2 arclim_sql

  $search->arclim_sql

  $search->arclim_sql( \%args )

Supported args are

  arclim
  prefix

Returns: The sql string to insert, beginning with "and ..."

=cut

sub arclim_sql
{
    my( $search, $args ) = @_;

    $args ||= {};

    my $arclim_in = $args->{'arclim'} || $search->arclim;
    my $arclim = RDF::Base::Arc::Lim->parse($arclim_in);


#    debug "Adding arclim_sql based on\n".datadump($arclim);
    my $sql = $arclim->sql({%$args,
			    active_on_date=>$search->{'arc_active_on_date'}});
#    debug "  -> ".$sql;

    return $sql ? "and $sql" : '';
}


##############################################################################

=head2 order_add

  $search->order_add($field)
  $search->order_add("$field $dir")
  $search->order_add(["$field $dir", ...])

See L<Para::Frame::List/sorted>

=cut

sub order_add
{

    # NOTE: Make sure that no item in the search result has two
    # properties with the same predicate, if that predicate is used in
    # the sorting

    my( $search, $extra_order ) = @_;

    foreach my $val ( @$extra_order )
    {
	push @{$search->{'query'}{'order_by'}}, $val;
	if( $val =~ /^score\b/ )
	{
	    $search->{'query'}{'sorttype'}{'score'} ++;
	}
    }

    $search->reset_sql;
}


##############################################################################

sub order_default
{
    my( $search, $new_order ) = @_;

    my $order_by = $search->{'query'}{'order_by'} ||= [];

    unless( @$order_by )
    {
	$search->order_add( $new_order );
    }

    $search->reset_sql;
    return 1;
}


##############################################################################

sub searchvals
{
    my( $prop ) = @_;

    my $type = $prop->{'type'};
    my $values = $prop->{'values'};
    my $match = $prop->{'match'};

    my( @searchvals );

    if( $type eq 'valclean' )
    {
	@searchvals = map valclean( $_ ), @$values;
    }
    else
    {
	@searchvals = @$values;
    }

    if( $match eq 'like' )
    {
	# Assume the SQL escape char is '\'
	foreach( @searchvals )
	{
	    s/\\/\\/g;
	    s/%/\%/g;
	    s/_/\_/g;
	    s/(.*)/%$1%/;
	}
    }
    elsif( $match eq 'begins' )
    {
	# Assume the SQL escape char is '\'
	foreach( @searchvals )
	{
	    s/\\/\\/g;
	    s/%/\%/g;
	    s/_/\_/g;
	    s/(.*)/$1%/;
	}
    }

    return \@searchvals;
}


##############################################################################

sub matchpart
{
    my( $match ) = @_;

    my $matchpart = $match || 'eq';

    $matchpart =~ s/eq/=/;
    $matchpart =~ s/exact/=/;
    $matchpart =~ s/gt/>/;
    $matchpart =~ s/lt/</;
    $matchpart =~ s/ne/=/;
    $matchpart =~ s/begins/like/;

    return $matchpart;
}


##############################################################################

sub parse_values
{
    my( $valref ) = @_;
    my @values;

    if( ref $valref eq 'ARRAY' )
    {
	@values = @$valref;
    }
    elsif( ref $valref eq 'RDF::Base::List' )
    {
	@values = $valref->nodes;
    }
    else
    {
	@values = ($valref);
    }

    foreach( @values )
    {
	if( ref $_ and UNIVERSAL::isa($_, 'RDF::Base::Resource') )
	{
	    # Getting node id
	    $_ = $_->id;
	}
	elsif( ref $_ eq 'HASH' )
	{
	    if( $_->{'id'} )
	    {
		$_ = $_->{'id'};
	    }
	    else
	    {
		# Sub-request
		$_ = RDF::Base::Resource->get_id( $_ );
	    }
	}

	# The string may have been octets in utf8 format but not
	# labled as utf8

        unless( defined $_ )
        {
            confess( datadump( $valref ) );
        }

        unless( ref $_ )
        {
            utf8::decode($_);
            utf8::upgrade($_);
        }
    }

    return \@values;
}


##############################################################################

sub sysdesig
{
    my( $search ) = @_;

    my $txt = "Query:\n";
    my $query = $search->{'query'};
    if( my $path = $query->{'path'} )
    {
	$txt .= "  Path:\n";
	foreach my $part ( keys %$path )
	{
	    $txt .= "    $part:\n";
	    foreach my $val ( @{$path->{$part}} )
	    {
		$txt .= sprintf("      %s\n", ref $val ? $val->sysdesig : $val );
	    }
	}
    }

    if( my $props = $query->{'prop'} )
    {
	$txt .= "  Prop:\n";
	foreach my $cond ( values %$props )
	{
	    my $key = $search->criterion_to_key( $cond );

#	    my $len1 = length($key);
#	    my $len2 = bytes::length($key);
#	    $txt .= sprintf "    $key (%d/%d):\n", $len1, $len2;
	    $txt .= "    $key:\n";

	    foreach my $val (@{$cond->{'values'}} )
	    {
		my $valout = $val;
		if( ref $val )
		{
		    if( UNIVERSAL::can($val, 'sysdesig') )
		    {
			$valout = $val->sysdesig;
		    }
		    else
		    {
			$valout = datadump( $val );
		    }
		}
		my $len1 = length($valout);
		my $len2 = bytes::length($valout);
		$txt .= sprintf "      $valout (%d/%d)\n", $len1, $len2;
	    }
	}
    }

    if( my $nodes = $query->{'node'} )
    {
	$txt .= "  Node:\n";
	foreach my $cond ( @$nodes )
	{
	    my $key = $search->criterion_to_key( $cond );

#	    my $len1 = length($key);
#	    my $len2 = bytes::length($key);
#	    $txt .= sprintf "    $key (%d/%d):\n", $len1, $len2;
	    $txt .= "    $key:\n";

	    foreach my $val (@{$cond->{'values'}} )
	    {
		my $valout = $val;
		if( ref $val )
		{
		    if( UNIVERSAL::can($val, 'sysdesig') )
		    {
			$valout = $val->sysdesig;
		    }
		    else
		    {
			$valout = datadump( $val );
		    }
		}
		my $len1 = length($valout);
		my $len2 = bytes::length($valout);
		$txt .= sprintf "      $valout (%d/%d)\n", $len1, $len2;
	    }
	}
    }

    if( my $qarc = $query->{'arc'} )
    {
	$txt .= "  QArc:\n";
	foreach my $key ( keys %$qarc )
	{
	    $txt .= "    $key:\n";

	    if( ref $qarc->{$key} )
	    {
		foreach my $val (@{$qarc->{$key}} )
		{
		    my $valout = $val||'';
		    if( ref $val )
		    {
			if( UNIVERSAL::can($val, 'sysdesig') )
			{
			    $valout = $val->sysdesig;
			}
			else
			{
			    $valout = datadump( $val );
			}
		    }
		    my $len1 = length($valout);
		    my $len2 = bytes::length($valout);
		    $txt .= sprintf "      $valout (%d/%d)\n", $len1, $len2;
		}
	    }
	    else
	    {
		my $valout = $qarc->{$key}||'';
		my $len1 = length($valout);
		my $len2 = bytes::length($valout);
		$txt .= sprintf "      $valout (%d/%d)\n", $len1, $len2;
	    }
	}
    }

    $txt .= "\n";
    return $txt;
}


##############################################################################

sub sql_sysdesig
{
    return $_[0]->sql_string .sprintf "; (%s)", join(", ", map{defined $_ ? "'$_'" : '<undef>'} @{$_[0]->sql_values} );

#    my( $search ) = @_;
#    my $out = $search->sql_string ."; ";
#
#    my @vals;
#    foreach my $val (@{$search->sql_values})
#    {
#	if( defined $val )
#	{
#	    my $length = length $val;
#	    push @vals, "'$val'($length)";
#	}
#	else
#	{
#	    push @vals, '<undef>';
#	}
#    }
#    $out .= sprintf "(%s)", join ', ', @vals;
#    return $out;
}


##############################################################################

sub sql_explain
{
    return;
}


##############################################################################

sub DESTROY
{
    my( $search ) = @_;

    $search->remove_node;
}

##############################################################################


1;


=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::List>

=cut
