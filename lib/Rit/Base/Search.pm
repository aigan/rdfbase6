#  $Id$  -*-cperl-*-
package Rit::Base::Search;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Search class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Search - Search directly in DB

=cut

use strict;
use Carp qw( cluck confess croak carp shortmess longmess );
use Time::HiRes qw( time );
use List::Util qw( min );
#use Sys::SigAction qw( set_sig_handler );

use constant TOPLIMIT   => 100000;
use constant MAXLIMIT   => 80;
use constant PAGELIMIT  =>  20;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Reload;

use Rit::Base::Utils qw( getpred valclean getnode );
use Rit::Base::Resource;
use Rit::Base::Pred;
use Rit::Base::List;
use Rit::Base::Lazy;

use base 'Clone'; # gives method clone()


=head1 DESCRIPTION

Represents one search project.

=cut


$Rit::DEBUG = 0;

our %DBSTAT;


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any Search object.

=cut

#######################################################################

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

#######################################################################

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

#######################################################################

=head2 result

Returns a L<Para::Frame::List>

=cut

sub result
{
    my( $search ) = @_;

    # May have a cb search result instead...
    my $res = $search->{'result'} or return Rit::Base::List->new_empty();

    confess(datadump($res)) if ref $res eq 'ARRAY';
    confess(datadump($search)) unless $res;

    my $limit = 10;
    my $req = $Para::Frame::REQ;
    my $user = $req->user;
    if( $user and $req->is_from_client )
    {
	my $q = $req->q;
	$limit = $q->param('limit') || 10;
	$limit = min( $limit, PAGELIMIT ) unless $user->has_root_access;
    }

    $res->set_page_size( $limit );

    return $res;
}

#######################################################################

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

    return $search->{'result'} = Rit::Base::List->new($list);
}

#######################################################################

=head2 reset_result

=cut

sub reset_result
{
    $_[0]->{'result'} = undef;
}

#######################################################################

=head2 result_url

=cut

sub result_url
{
    $_[0]->{'result_url'} = $_[1] if defined $_[1];
    return $_[0]->{'result_url'} ||
      $Para::Frame::REQ->site->home->url_path_slash;
}

#######################################################################

=head2 form_url

=cut

sub form_url
{
    $_[0]->{'form_url'} = $_[1] if defined $_[1];
    return $_[0]->{'form_url'} ||
      $Para::Frame::REQ->site->home->url_path_slash;
}

#######################################################################

=head2 add_stats

  $s->add_stats

  $s->add_stats($bool)

Gets/sets a boolean value if this search should be added to the
statistics using L<Rit::Base::Resource/log_search>.

=cut

sub add_stats { $_[0]->{'add_stats'} = $_[1] if defined $_[1]; $_[0]->{'add_stats'} }

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

#######################################################################

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

#######################################################################

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


    # Set MAXLIMIT.
    # Start limited. Set it wider if search is restricted to something

    if( $args->{'maxlimit'} )
    {
	$search->{'maxlimit'} = $args->{'maxlimit'};
#	debug "Maxlimit set\n";
    }
    else
    {
	$search->{'maxlimit'} = MAXLIMIT;

	# searching will be done before we have a user obj
	if( my $user = $Para::Frame::REQ->user )
	{
	    $search->{'maxlimit'} = $user->level >= 20 ? TOPLIMIT : MAXLIMIT;
	}
    }

    debug 3, "Search object resetted";
    return $search;
}

#######################################################################

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
				 ref $values eq 'Rit::Base::List' )
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
    $q->param('query', $query);

    return $query;
}

#######################################################################

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
	    next if $vals{$val} ++;
	    push @values, $val;
	}

	$q->param( -name=>$prop, -values=> \@values );
    }

    # Return true if search is non-empty
    return scalar %$props;
}

#######################################################################

=head2 modify_from_query

=cut

sub modify_from_query
{
    my( $search ) = @_;

    my $q = $Para::Frame::REQ->q;

    my %props;
    foreach my $key ( $q->param() )
    {
         if( $key eq 'remove' )
         {
             foreach my $remove ( $q->param($key) )
             {
                 my( $type, $target ) = split(/_/, $remove, 2 );
                 $search->broaden( $type, $target );
             }
         }


	#filter out other params
	next unless $key =~ /^(revprop_|prop_|order_by|path_)/;

	my( @vals ) =  $q->param($key);

	# Convert param key
	$key =~ s/^revprop_/rev_/;
	$key =~ s/^prop_//;

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
	    push @{ $props{$key} }, @values;
	}
    }
    $search->modify( \%props );
}

#######################################################################

=head2 broaden

Broaden never keeps predor-preds... Bug to fix later...

=cut

sub broaden # removes targets from searchy type
{
    my( $search, $type, $target ) = @_;

    $search->remove_node;

    if( UNIVERSAL::isa( $target, 'Rit::Base::Literal' ) )
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
		my @pred_names = map $_->name->plain, $preds->as_array;
		$predkey = 'predor_'.join('_-_', @pred_names);
	    }
	    else
	    {
		$predkey = $preds->get_first_nos->name->plain;
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

#######################################################################

=head2 modify

  $search->modify( \%crits )

  $search->modify( \%crits, \%args )

C<%crits> consists of key/value pairs. The values can be an arrayref,
a L<Rit::Base::List> or a single value.

Each value can be a L<Rit::Base::Resource> object, a ref to a hash
containing an C<id> key or a ref to a hash in the form of a
subrequest. The id will be extracted by calling
L<Rit::Base::Resource/get_id>.

Empty values are valid. (That includes fales values, empty strings and
undef values or undef objects.)

The C<%args> is used for all C<%crits>.

  private: Can be used to hide some properties in the presentation of
a search object.

  clean: Sets the clean property for each criterion.


The keys are built up of parts used to describe the type of search
part (search criterion).

The search format should be compatible with L<Rit::Base::List/find>.

=head3 path

currently only used in one place in search/fairs.tt

This type of search may be removed removed in the future

=head3 order_by

Calls L</order_add> with the given values.

This functionality may be moved to L</modify_from_query>.

=head3 Main search key format

  <rev> _ <pred> _ <arctype> _ <clean> _ <comp> _ <prio>

All parts except C<pred> is optional.

Example: rev_in_region_explicit_clean_begins_2

Perl does a non-greedy match to extract all the parts from the key.

C<rev>: C<rev> indicates a reverse property.

C<pred>: Any predicate name.

C<actype>: Any of C<direct>, C<indirect>, C<explicit>,
C<implicit>. Those are criterions for the arcs to match.

C<clean>: If C<clean>, uses the clean version of strings in the
search.

C<comp>: Any of C<eq>, C<like>, C<begins>, C<gt>, C<lt>, C<ne>,
C<exist>.

C<prio>: One or more digits.



Returns: 1

=cut

sub modify
{
    my( $search, $props, $args ) = @_;

    $search->remove_node;

    debug 3, shortmess "modify search ".datadump( $props, 3); ### DEBUG
    unless( ref $props eq 'HASH' )
    {
	confess "modify called with faulty props: ".datadump($props);
    }

    $args ||= {};

    my $private = $args->{'private'} || 0;

    foreach my $key ( keys %$props )
    {
	# Set up values supplied
	#
	my $valref = $props->{ $key };
	my @values;

	if( ref $valref eq 'ARRAY' )
	{
	    @values = @$valref;
	}
	elsif( ref $valref eq 'Rit::Base::List' )
	{
	    @values = $valref->nodes;
	}
	else
	{
	    @values = ($valref);
	}

	foreach( @values )
	{
	    if( ref $_ and UNIVERSAL::isa($_, 'Rit::Base::Resource::Compatible') )
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
		    $_ = Rit::Base::Resource->get_id( $_ );
		}
	    }
	}

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
	elsif ($key =~ m/^(rev_)?(.*?)(?:_(direct|indirect|explicit|implicit))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/x)
	{
	    my $rev    = $1;
	    my $pred   = $2;
	    my $predref;
	    my $type;
	    my $arclim = $3; ### TODO: test this
	    my $clean  = $4 || 0;
	    my $match  = $5 || 'eq';
	    my $prio   = $6; #Low prio first (default later)

	    if( $arclim )
	    {
		confess "not implemented ($key)";
	    }

	    if( $pred =~ s/^predor_// )
	    {
		my( @prednames ) = split /_-_/, $pred;
		my( @preds ) = map Rit::Base::Pred->get($_), @prednames;
		$predref = \@preds;

		# Assume no type mismatch between alternative preds
		$type = $preds[0]->coltype($props); # FIXME: invalid parameter $props
	    }
	    elsif( $pred =~ /^count_pred_(.*)/ )
	    {
		confess "not implemented: $pred";
	    }
	    else
	    {
		$pred = Rit::Base::Pred->get( $pred );
		$type = $pred->coltype($props);
		$predref = [$pred];
	    }

	    if( $values[0] eq '*' )
	    {
		$match = 'exist';
	    }

	    if( $type eq 'valtext' )
	    {
		if( $clean )
 		{
 		    $type = 'valclean';
 		}
	    }
	    elsif( $type eq 'obj' )
	    {
		# The obj part can be specified in several ways
		#
		my @new;
		foreach my $val ( @values )
		{
		    if( ref $val and UNIVERSAL::isa( $val, 'Rit::Base::Object::Compatible' ) )
		    {
			unless( $val->defined )
			{
			    $val = undef;
			}
		    }

		    if( defined $val and length $val )
		    {
			push @new, Rit::Base::Resource->resolve_obj_id( $val );
		    }
		    else
		    {
			push @new, undef;
		    }
		}
		@values = @new;
	    }

	    if( $match eq 'exist' )
	    {
		@values = ();
	    }
	    elsif( not @values )
	    {
		throw('incomplete', longmess("Values missing: ".datadump $search->{'query'}{'prop'}));
	    }

	    if( $rev )
	    {
		$type = 'sub';
	    }

	    $search->add_prop({
		rev => $rev,
		pred => Rit::Base::List->new($predref),
		type => $type,
		match => $match,
		clean => $clean,
		values => \@values,
		prio => $prio,   # Low prio first
		private => $private,
		arclim => $arclim,
	    });


	    # Modify MAXLIMIT
	    # - Change maxlimit if search on city
	    if( UNIVERSAL::isa($pred, 'Rit::Base::Pred') and $pred->name->plain eq 'is' and getnode('city')->equals($values[0]) )
	    {
		debug 2, "*** Maxlimit changed!";
		$search->{'maxlimit'} = TOPLIMIT;
	    }
	}
	else
	{
	    die "wrong format in find: $key\n";
	}
    }

    $search->reset_sql;

    return 1;
}

#######################################################################

=head2 execute

=cut

sub execute
{
    my( $search ) = @_;

    my( $sql, $values, $min_prio ) = $search->build_sql;
    unless( $sql )
    {
	debug "Executing an empty search...";
	return '';
    }

    my $result;

    if( $min_prio > 5 )
    {
	debug "Search is to heavy! Runs in background";
	debug $search->sysdesig;
#	debug $search->sql_sysdesig;

	my $req = $Para::Frame::REQ;
	$req->note("This search may take a some time!");
	my $fork = $req->create_fork;
	if( $fork->in_child )
	{
	    $fork->return( $search->get_result($sql, $values, 240) ); # 60
	}
	my $fres = $fork->yield;
#	debug "GOT BACK <<<<<<<<<<<<-----------------";
	$result = $fres->message;
#	debug "Have result, will die";
#	throw('dbi',"Timeout reached") if $fres->exception;
    }
    else
    {
#	debug "MIN PRIO = $min_prio";
	if( debug > 2 )
	{
	    debug $search->sysdesig;
	    debug 4, $search->sql_sysdesig;
	}
	$result = $search->get_result($sql, $values, 15); # 10
    }

    $search->{'result'} = Rit::Base::List->new($result);

    debug(3, "Got result ".datadump($search->{'result'}));

    return '';
}


#######################################################################

sub get_result
{
    my( $search, $sql, $values, $timeout ) = @_;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare( $sql );

    $timeout ||= 20;

    my $time = time;
    eval
    {
	$dbh->do(sprintf "set statement_timeout = %d", $timeout*1000);
	$sth->execute(@$values);
	$dbh->do("set statement_timeout = 0000");
    };
    if( $@ )
    {
	if( $Rit::dbix->state->is('query_canceled') )
	{
	    debug $search->sysdesig;
	    debug $search->sql_sysdesig;
	    throw('dbi', "Database search took to long");
	}

	throw('dbi',  $@ . "Values: ".join(", ", map{defined $_ ? "'$_'" : '<undef>'} @$values)."\n");
    }

    if( debug > 2 )
    {
	my $took = time - $time;
	debug(sprintf("Execute: %2.2f", $took));
	debug $search->sysdesig;
	debug $search->sql_sysdesig;
    }

    my( @result, %found );
    while( my( $sub, $score ) = $sth->fetchrow_array )
    {
	# We save execution time by not eliminating all duplicates
	if( $found{ $sub } ++ )
	{
	    # Duplicate found. Subtract number of hits
	    next;
	}

	push @result, $sub;
	last if $#result >= $search->{'maxlimit'} -1;
    }
    $sth->finish;

#    debug sprintf "Got %d hit", scalar(@result);
#    debug datadump(\@result); ### DEBUG

    return \@result;
}


#######################################################################

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

    # props
    if( my $props = $search->{'query'}{'prop'} )
    {
#	debug datadump($props); ### DEBUG
	push @elements, @{ $search->elements_props( $props ) };
    }

    unless( @elements ) # Handle empty searches
    {
	debug( 2, "*** Empty search");
	$search->{'result'} = Rit::Base::List->new_empty();
	return();
    }

    my @outer_score = ();
    my @main_select = ();
    my @main_where = ();
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

    if( debug > 2 )
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
	$sql .= " limit ?";
	push @values, $limit;
    }


    my $values = \@values; # Lock ref
    $search->{'sql_string'} = $sql;
    $search->{'sql_values'} = $values;
    $search->{'min_prio'} = $min_prio;

    return( $sql, $values, $min_prio );
}

sub sql_string
{
    return $_[0]->{'sql_string'};
}

sub sql_values
{
    return $_[0]->{'sql_values'};
}

sub reset_sql
{
    $_[0]->{'sql_string'} = undef;
    $_[0]->{'sql_values'} = undef;
}


#######################################################################

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
	$node = Rit::Base::Resource->create({is=>'search'});

	foreach my $prop ( values %{$search->{'query'}{'prop'}} )
	{
	    my $preds = $prop->{'pred'};
	    unless( UNIVERSAL::isa( $preds, 'Para::Frame::List' ) )
	    {
		$preds = Rit::Base::List->new([$prop->{'pred'}]);
	    }

	    foreach my $pred ( $preds->as_array )
	    {
		my $values = $prop->{'values'};

		$node->add({ $pred->name => $values });
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
	if( $Rit::Base::Cache::Resource{ $node->id } )
	{
	    $node->remove;
	}

	delete $search->{'node'};
    }
}



#######################################################################

sub add_prop
{
    my( $search, $rec ) = @_;

    ## pred is always an object here, I guess
    my $preds = $rec->{'pred'};



    my $pred_key = join ',', map $_->id, $preds->as_array;
    my $rev = $rec->{'rev'}||'';
    my $match = $rec->{'match'}||'';
    my $key = join('-', $pred_key, $rev, $match);
    $key .= '='.join '+', map{ref $_ ? $_->syskey : Rit::Base::Literal->new($_)->syskey} @{$rec->{'values'}};

    $rec->{'key'} = $key;
    my $pred_name = "";
    if( $preds->size == 1 )
    {
	my $first = $preds->get_first_nos;
	$pred_name = $first->name->plain;
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


#######################################################################

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


#######################################################################

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
	elsif( $cc eq 'orcer_by' )
	{
	    # Limited support
	    $props->{"order_by"} = $search->{'query'}{'order_by'}[0];
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

#		debug "VALUES: @$values";

		foreach my $val ( @$values )
		{
		    if( ref $val and UNIVERSAL::isa( $val, 'Rit::Base::Resource::Compatible') )
		    {
			$val = $val->name->loc;  # Changes val i array
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
		    $pred_alt = $pred->name->plain;
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

		    if( ref $p and UNIVERSAL::isa( $p, 'Rit::Base::Resource::Compatible') )
		    {
			$str .= $p->name;
		    }
		    else
		    {
			$str .= $p;
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


#######################################################################

=head2 criterions

Transform search to set of PUBLIC explained criterions.

props:	push( @{$ecrits->{$pred_name}{'prop'}}, $prop );

$pred_name is in a form equal to the one used in html forms

$prop is the value node

=cut

sub criterions
{
    my( $search ) = @_;

#    debug "Getting criterions";

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
		next if $prop->{'private'};

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
		    my $ors = join '_-_', map $_->name->plain, $preds->as_array;
		    $pred_name = "predor_$ors";
		}
		else
		{
		    $pred_name = $preds->get_first_nos->name->plain;
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
	debug "  No criterions found";
	return undef;
    }
}


#######################################################################

sub criterion_to_key
{
    my( $search, $cond ) = @_;

    my $rev = $cond->{'rev'};
    my $preds = $cond->{'pred'};
    my $match = $cond->{'match'};

    my $prio = $cond->{'prio'} ||= set_prio( $cond );

    my $pred_name;
    if( $preds->size > 1 )
    {
	my $ors = join '_-_', map $_->name->plain, $preds->as_array;
	$pred_name = "predor_$ors";
    }
    else
    {
	$pred_name = $preds->get_first_nos->name->plain;
    }

    if( $rev )
    {
	$pred_name = "rev$pred_name";
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



#######################################################################

sub build_outer_order
{
    my( $search, $sortkeys ) = @_;

    my $sql = join ", ", @$sortkeys;
    my @values = ();

    return( $sql, \@values );
}


#######################################################################

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


#######################################################################

sub build_outer_select
{
    my( $search, $scores ) = @_;

    my @parts = ();
    my @values = ();
    my @sortkeys = ();

    push @parts, 'node as sub';

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


#######################################################################

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


#######################################################################

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


#######################################################################

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

	my $part_sql = join " UNION ", map "select 1 from rel where $select=main.node and $_", @where;

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


#######################################################################

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
	    $part_sql .= join " UNION ", map "select $part->{'select'} as node from rel where $_", @where;
	}
	else
	{
	    ### DEBUG
	    unless($part->{'select'})
	    {
		confess datadump( $part );
	    }

	    # TODO:
	    # We save more time in the common case if we only use 'distinct'
	    # in cases it relay cuts down the number of records
	    #
	    $part_sql .= "select distinct $part->{'select'} from rel";
	}

	push @part_sql_list, $part_sql;
	push @values, @{$part->{'values'}};
    }

    my $intersect = join " INTERSECT ", map "($_)", @part_sql_list;


    my $sql    = "( $intersect ) as main";

    return( $sql, \@values );
}


#######################################################################

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
	push @parts, build_main_select_price();
    }

   my $sql = join(", ", @parts);


    return( $sql, \@values );
}


#######################################################################

sub build_outer_select_field
{
    # NB! No longer sorts result using clean

    my( $search, $field_in ) = @_;

    my $fieldpart = $field_in or confess "Param field missing";

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

	my $pred = Rit::Base::Pred->get( $field );
	my $coltype = $pred->coltype;

# Sort on real value. Not clean
#	if( $coltype eq 'valtext' )
#	{
#	    $coltype = 'valclean';
#	}

	my $where = "sub=frame.node";
	if( $sql )
	{
	    $where = "sub in ($sql)";
	}

	if( $tr )
	{
	    # Sort by weight
	    $sql ="select $coltype from (select CASE WHEN obj is not null THEN (select $coltype from rel where pred=4 and sub=${sortkey}_inner.obj) ELSE $coltype END, CASE WHEN obj is not null THEN (select valint from rel where pred=302 and sub=${sortkey}_inner.obj) ELSE 0 END as weight from rel as ${sortkey}_inner where $where and pred=? order by weight limit 1) as ${sortkey}_mid";
	}
	else
	{
	    $sql = "select $coltype from rel where $where and pred=? limit 1";
	}
	    push @values, $pred->id;
    }

    $sql = "($sql) as $sortkey";


    debug "SORT SQL: $sql";
    return( $sql, \@values, "$sortkey $dir" );
}


#######################################################################

sub build_main_select_group
{
    my( $elems ) = @_;

    my @parts = ();
    my @values = ();
    foreach my $elem ( @$elems )
    {
	### 'Distinct' evades error from dirty DB data
	my $sql = "select distinct $elem->{'select'} ";
	$sql   .= "from rel ";
	$sql   .= "where sub=main.node and ";
	$sql   .= $elem->{'where'};

	$sql = "($sql) as ".$elem->{'name'};

	push @parts, $sql;
	push @values, @{$elem->{'values'}};
    }

    return( \@parts, \@values );
}


#######################################################################

sub build_main_select_price
{
    # rel1 is the has_subscription relation and rel2 is the weight relation of the specific subscription object.

    my $sql =
"
              (
               select sum(rel2.valint)
               from rel as rel1, rel as rel2
               where
                   rel1.sub=main.node and rel1.obj=rel2.sub and rel2.pred=302 and rel1.indirect is false and
                   exists
                   (
                       select 1
                       from rel
                       where sub=rel2.sub and pred=1 and obj=1111
                   )
               group by rel1.sub
           ) as price
";

    return $sql;
}


#######################################################################

sub elements_path
{
    my( $search, $paths ) = @_;

    my @element;
    foreach my $path ( keys %$paths )
    {
	my( $where, $path_values, $prio ) = $search->build_path_part( $paths->{$path} );

	push @element,
	{
	    select => 'sub',
	    where => $where,
	    values => $path_values,
	    prio => $prio,
	};
    }

    return( \@element );
}


#######################################################################

sub elements_props
{
    my( $search, $props ) = @_;

    my @element;
    foreach my $cond ( values %$props )
    {
	my $rev = $cond->{'rev'};
	my $preds = $cond->{'pred'}; # The obj or obj list
	my $type = $cond->{'type'};
	my $match = $cond->{'match'} ||= 'eq';
	my $invalues = $cond->{'values'};
	my $prio = $cond->{'prio'};

	my $negate = ( $match eq 'ne' ? 1 : 0 );

	unless( $prio )
	{
	    $prio = set_prio( $cond );
	}

	my $select = ($rev ? 'obj' : 'sub');
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

		if( $pred->name->plain eq 'id' )
		{
		    die "not implemented";
		}
		else
		{
		    push @parts, "pred=?";
		    push @pred_ids, $pred->id;
		}
	    }
	    $pred_part = "(".join(" or ", @parts).")";
	}
	else
	{
#	    debug( 2, sprintf "Prio for %s is $prio", $pred->desig);

	    @pred_ids = $preds->get_first_nos->id;
	    $pred_part = "pred=?";
	}


	if( $match eq 'exist' )        # match any
	{
	    $where = $pred_part;
	    @outvalues = @pred_ids;
	}
	elsif( $invalues->[0] eq '*' ) # match all
	{
	    $where = $pred_part;
	    @outvalues = @pred_ids;
	}
	elsif( ($preds->size < 2) and
	       ($preds->get_first_nos->name->plain eq 'id') )
	{
	    $where = join(" or ", map "sub = ?", @$invalues);
	    @outvalues = @$invalues; # value should be numeric
	    $prio = 1;
	}
	else
	{
	    confess "In elements_props: ".datadump $cond unless $type; ### DEBUG

	    my $matchpart = matchpart( $match );
	    $matchpart = join(" or ", map "$type $matchpart ?", @$invalues);
	    my @matchvalues =  @{ searchvals($cond) };

	    ### Support matching valuenodes
	    if( $type ne 'obj' )
	    {
		# See time comparsion in doc/notes2.txt
		$where =
		  [
		   "$pred_part and obj in ( select sub from rel where pred=4 and ($matchpart) )",
		   "$pred_part and ($matchpart)",
		  ];
		@outvalues = ( @pred_ids, @matchvalues, @pred_ids, @matchvalues );
	    }
	    else
	    {
		$where = "$pred_part and ($matchpart)";
		@outvalues = ( @pred_ids, @matchvalues);
	    }
	}

	if( $search->add_stats )
	{
#	    debug sprintf("--> add stats for props search? (type $type, pred %s, vals %s)\n",
#			 $pred->name, join '-', map $_, @$invalues);
	    if( $type =~ /^(obj|sub|id)$/ )
	    {
		foreach my $node_id ( @$invalues )
		{
		    getnode($node_id)->log_search;
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


#######################################################################

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

    my $path = $path_rec->{'path'};
    my $values = $path_rec->{'values'};
    my $clean = $path_rec->{'clean'};

    my( @steps ) = split /__/, $path;

    my $last_step = pop @steps;
    my $first_step = shift @steps;

    #### LAST STEP

    my $pred = Rit::Base::Pred->get( $last_step );
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

    my $value_part = join " or ", map "$coltype=?", @$values;
    my $where = "pred=? and ($value_part)";
    my @path_values = $pred->id;
    push @path_values, @$values;


    #### MIDDLE STEPS

    foreach my $step ( reverse @steps )
    {
	my $pred_id = Rit::Base::Pred->get_id($step);

	$where = "pred=? and obj in (select sub from rel where $where)";
	unshift @path_values, $pred_id;
    }

    my $sql = "select sub from rel where $where";

#    my $time = time;
    my $result = $Rit::dbix->select_list( $sql, @path_values );
#    my $took = time - $time;
#    debug sprintf("Try path list: %2.2f\n", $took);


    #### FIRST STEP

    my $pred_part;
    my @pred_ids;
    if( $first_step =~ s/^predor_// )
    {
	my( @preds ) = split /_-_/, $first_step;
	( @pred_ids ) = map Rit::Base::Pred->get_id($_), @preds;

	$pred_part = join " or ", map "pred=?", @pred_ids;
	$pred_part = "($pred_part)";
	unshift @path_values, @pred_ids;
    }
    else
    {
	$pred_part = "pred=?";
	( @pred_ids ) = Rit::Base::Pred->get_id($first_step);
	unshift @path_values, @pred_ids;
    }

    if( $search->add_stats )
    {
	foreach my $rec ( @$result )
	{
	    getnode($rec->{'sub'})->log_search;
	}
    }

    if( @$result > 1 )
    {
	$where = "$pred_part and obj in( $sql )";
	return( $where, \@path_values, 7);
    }
    elsif( @$result )
    {
	my $value = $result->[0]->{'sub'};
	return( "$pred_part and obj=?", [@pred_ids, $value], 2);
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


#######################################################################

sub set_prio
{
    my( $cond ) = @_;

    my $preds = $cond->{'pred'};
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
	    return 8;
	}
	return 7;
    }
    elsif( scalar(@$vals) > 5 )
    {
	return 8;
    }
    elsif( $preds->size > 1 ) #alternative preds
    {
	$key = join('-', map $_->plain, $preds->as_array);
	if( $key eq 'name-name_short-code' ){ return 3 }

	$key .= '='.join ',', @$vals;
	return $DBSTAT{$key} if defined $DBSTAT{$key};

	$coltype = $first_pred->coltype();
	my @predid = map $_->id, $preds->as_array;
	my $sqlor = join " or ", map "pred=?", @predid;
	my $valor = join " or ", map "$coltype=?", @$vals;
	my $sql = "select count(sub) from rel where ($sqlor)";
	if( $valor )
	{
	    $sql .= " and ($valor)";
	}
	my $sth = $Rit::dbix->dbh->prepare( $sql );
	my @values = (@predid, @$vals);

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
	$prio = 2;
    }
    else
    {
	if( $first_pred->plain eq 'id'       ){ return  1 }
	if( $first_pred->plain eq 'value'    ){ return 10 }
	if( $first_pred->plain eq 'name'     ){ return  2 }
	$coltype = $first_pred->coltype();
	if( $coltype eq 'valtext'      ){ return  3 }

	$key = $first_pred->plain;
	$key .= '='.join ',', @$vals;
	return $DBSTAT{$key} if defined $DBSTAT{$key};

	my $valor = join " or ", map "$coltype=?", @$vals;
	my $sql = "select count(sub) from rel where (pred=?)";
	if( $valor )
	{
	    $sql .= " and ($valor)";
	}
	my $sth = $Rit::dbix->dbh->prepare( $sql );
	my @values = ($first_pred->id, @$vals);

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
	$prio = 1;
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


#######################################################################

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


#######################################################################

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


#######################################################################

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
	@searchvals = map "%$_%", @searchvals;
    }
    elsif( $match eq 'begins' )
    {
	@searchvals = map "$_%", @searchvals;
    }

    return \@searchvals;
}


#######################################################################

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


#######################################################################

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
		$txt .= "      $valout\n";
	    }
	}
    }
    $txt .= "\n";
    return $txt;
}


#######################################################################

sub sql_sysdesig
{
    return $_[0]->sql_string .sprintf "; (%s)", join(", ", map{defined $_ ? "'$_'" : '<undef>'} @{$_[0]->sql_values} );
}


#######################################################################

sub sql_explain
{
    return;
}


#######################################################################

sub DESTROY
{
    my( $search ) = @_;

    $search->remove_node;
}

#######################################################################


1;


=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::List>

=cut
