package RDF::Base::Node;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2016 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Node

=cut

use 5.010;
use strict;
use warnings;
use vars qw($AUTOLOAD);
use base qw( RDF::Base::Object );

use Carp qw( cluck confess croak carp longmess );

use Para::Frame::Utils qw( throw catch debug datadump trim );
use Para::Frame::Reload;

use RDF::Base::Arc::Lim;
use RDF::Base::Utils qw(valclean parse_query_props
                        is_undef arc_lock
                        arc_unlock truncstring query_desig
                        convert_query_prop_for_creation
                        parse_propargs aais parse_query_value range_pred );


=head1 DESCRIPTION

Base class for L<RDF::Base::Resource> and L<RDF::Base::Literal>.

Inherits from L<RDF::Base::Object>.

=cut

##############################################################################

=head1 Object creation

1. Call Class->get($identity)

If you know the correct class, call get for that class. Resource
handles the get(). Get handles node chaching.

2. get() calls Class->new($id), blesses the object to the right class
and then calls $obj->init()

3. new($id) calls $obj->initiate_cache, that handles the Resource
cahce part. Caching specific for a subclass must be handled outside
this, in init()

4. init() will store node in cache if not yet existing

The create() method creates a new object and then creates the object
and calls init()

A get_by_rec($rec) will get the node from the cache or create an
object and call init($rec)


=cut


##############################################################################

=head2 is_node

Returns true.

=cut

  sub is_node { 1 };


##############################################################################

=head2 is_resource

Returns false.

=cut

sub is_resource { 0 };


##############################################################################

=head2 parse

  $n->parse( $value, \%args )

Compatible with L<RDF::Base::Literal/parse>. This just calls
L<RDF::Base::Resource/get_by_anything> with the same args.

Supported args:

  valtype
  arc

Returns: the value as a literal or resource node

=cut

sub parse
{
    return shift->get_by_anything( @_ );
}


##############################################################################

=head2 new_from_db

  $n->parse( $value )

Compatible with L<RDF::Base::Literal/new_from_db>. This just calls
L<RDF::Base::Resource/get> the given C<$value>

Returns: the value as a resource node

=cut

sub new_from_db
{
    return $_[0]->get( $_[1] );
}


##############################################################################

=head2 find_remove

  $n->find_remove(\%props, \%args )

Remove matching nodes if existing.

Calls L</find> with the given props.

Calls L</remove> for each found node.

For arcs, the argument C<implicit>, if given, is passed on to
L</remove>. This will only remove arc if it no longer can be infered
and it's not explicitly declared

If the node is an arc and C<force> is not true, it will not remove an arc that is a removal or that has been deactivated.

Supported args:

  arclim
  res
  implicit
  force

Returns: ---

=cut

sub find_remove
{
    my( $this, $props, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $force = $args->{'force'} || 0;

#    debug "Find for removal:\n".query_desig($props);
#    debug query_desig($args);

    arc_lock;
    foreach my $node ( $this->find( $props, $args )->nodes )
    {
        if ( $node->is_arc and not $force )
        {
            next if $node->is_removal;
            next if $node->old;
        }

        $node->remove( $args );
    }
    arc_unlock;

}


##############################################################################

=head2 id_alphanum

  $n->id_alphanum

The unique node id expressed with [0-9A-Z] as a plain string, with a
one char checksum at the end.

=cut

sub id_alphanum
{
    my $id = $_[0]->id;
    my $str = "";
    my @map = ((0..9),('A'..'Z'));
    my $len = scalar(@map);
    my $chksum = 0;
    while ( $id > 0 )
    {
        my $rest = $id % $len;
        $id = int( $id / $len );

        $str .= $map[$rest];
        $chksum += $rest;
    }

    return reverse($str) . $map[$chksum % $len];
}


##############################################################################

=head2 parse_prop

  $n->parse_prop( $criterion, \%args )

Parses C<$criterion>...

Returns the values of the property matching the criterion.  See
L<RDF::Base::Resource/list> for explanation of the params.

See also L<RDF::Base::List/parse_prop>

=cut

sub parse_prop
{
    my( $node, $crit, $args_in ) = @_;

    $crit or confess "No name param given";
    return  $node->id if $crit eq 'id';

    my( $args, $arclim ) = parse_propargs($args_in);
#    debug "Parsing $crit";

    my $step;
    if ( $crit =~ s/\.(.*)// )
    {
        $step = $1;
    }

    my($prop_name, $propargs) = split(/\s+/, $crit, 2);
    trim(\$prop_name);
    my( $proplim, $arclim2 );
    if ( $propargs )
    {
        ($proplim, $arclim2) = parse_query_value($propargs);
        if ( $arclim2 )
        {
            $args->{'arclim'} = $arclim2;
        }
    }

    if ( $prop_name =~ s/_(@{[join '|', @{RDF::Base::Arc::Lim->names}]})$//o )
    {
        if ( $arclim2 )
        {
            die "Do not mix arclim syntax: $prop_name";
        }
        $args->{'arclim'} = RDF::Base::Arc::Lim->parse($1);
    }

    my $res;
    if ( $prop_name =~ s/^rev_// )
    {
        $res = $node->revprop( $prop_name, $proplim, $args );
    }
    else
    {
#        debug "node isa ".ref($node);
#        if( $node->is_list )
#        {
#            my $first = $node->get_first_nos;
#            debug "First in list isa ".ref($first);
#        }


        if ( $node->can($prop_name) )
        {
#            debug "  Calling method $prop_name";
            $res = $node->$prop_name($proplim, $args);
        }
        else
        {
#            debug "  Calling prop $prop_name";
            $res = $node->prop( $prop_name, $proplim, $args );
        }
    }

    if ( $step )
    {
#        debug "  calling $res -> $step";
#        debug "  res is ".ref($res);

        my $res2 = $res->parse_prop( $step, $args_in );
#        debug "  res2 $res2";
        return $res2;
    }

#    debug "  res $res";
    return $res;
}


##############################################################################

=head2 prop

  $n->prop( $predname, undef, \%args )

  $n->prop( $predname, $proplim, \%args )

  $n->prop( $predname, $value, \%args )

Returns the values of the property with predicate C<$predname>.  See
L<RDF::Base::Resource/list> for explanation of the params.

For special predname C<id>, returns the id.

Use L</first_prop> or L<RDF::Base::Resource/list> instead if that's what you want!

If given a value instead of a proplim, returns true/false based on if
the node has a property with the specified $predname and $value.

Returns:

If more then one node found, returns a L<RDF::Base::List>.

If one node found, returns the node.

In no nodes found, returns C<is_undef>.

For C<$value>, returns the given $value, or C<is_undef>

=cut

sub prop
{
    my $node = shift;
    my $name = shift;

    $name or confess "No name param given";
    return  $node->id if $name eq 'id';

    debug 3, "!!! get ".($node->id||'<undef>')."-> $name";

    confess "loc is a reserved dynamic property" if $name eq 'loc';
    confess "This node is not an arc: ".datadump($node,2) if $name eq 'subj';

    my $values = $node->list($name, @_);

    unless( $values )
    {
        return is_undef;
    }

    if ( $values->size > 1 )    # More than one element
    {
        return $values;         # Returns list
    }
    elsif ( $values->size ) # Return Resource, or undef if no such element
    {
        return $values->get_first_nos;
    }
    else
    {
        return is_undef;
    }
}


##############################################################################

=head2 revprop

  $n->revprop( $predname )

  $n->revprop( $predname, $proplim )

  $n->revprop( $predname, $proplim, \%args )

Returns the values of the reverse property with predicate
C<$predname>.  See L<RDF::Base::Resource/list> for explanation of the params.

Returns:

If more then one node found, returns a L<RDF::Base::List>.

If one node found, returns the node.

In no nodes found, returns C<undef>.

=cut

sub revprop
{
    my $node = shift;
    my $name = shift;

    $name or confess "No name param given";

    my $values = $node->revlist($name, @_);

    if ( $values->size > 1 )    # More than one element
    {
        return $values;         # Returns list
    }
    elsif ( $values->size ) # Return Resource, or undef if no such element
    {
        return $values->get_first_nos;
    }
    else
    {
        return is_undef;
    }
}


##############################################################################

=head2 has_pred

  $n->has_pred( $pred )

  $n->has_pred( $pred, $proplim, $arclim )

Return true if the node has at least one property with this predicate.
The return values makes this method usable as a filter.

Example:

  m.revlist('our_reference').has_pred('contact_next').sorted('contact_next')

Returns:

True: The node

False: is_undef

=cut

sub has_pred
{
    my( $node ) = shift;

    if ( $node->first_prop(@_)->size )
    {
        return $node;
    }
    else
    {
        return is_undef;
    }
}


##############################################################################

=head2 has_revpred

  $n->has_revpred( $pred )

  $n->has_revpred( $pred, $proplim, $arclim )

The reverse of has_pred.  Return true if the node has at least one
B<ACTIVE> reverse property with this predicate.

Returns:

True: The node

False: is_undef

=cut

sub has_revpred
{
    my( $node ) = shift;

    if ( $node->first_revprop(@_)->size )
    {
        return $node;
    }
    else
    {
        return is_undef;
    }
}


##############################################################################

=head2 meets_proplim

  $n->meets_proplim( $proplim, \%args )

  $n->meets_proplim( $object, \%args )

See L<RDF::Base::List/find> for docs.

Also implements predor

This also implements meets_proplim for arcs!!!

Also implements the form mypred1{is this}.that

... implements not => { ... }

Returns: boolean

=cut

sub meets_proplim
{
    my( $node, $proplim, $args_in_in ) = @_;
    my( $args_in, $arclim_in ) = parse_propargs($args_in_in);

    # TODO: Eliminate parse_propargs!!!

#    Para::Frame::Logging->this_level(4);
    my $DEBUG = Para::Frame::Logging->at_level(3);

    unless( ref $proplim and ref $proplim eq 'HASH' )
    {
        return 1 unless $proplim;
        return $node->equals( $proplim, $args_in );
    }

    if ( $DEBUG )
    {
        debug "Checking ".$node->sysdesig;
        debug "Args ".query_desig($args_in);
    }


  PRED:
    foreach my $pred_part ( keys %$proplim )
    {
        my $target_value =  $proplim->{$pred_part};
        if ( $DEBUG )
        {
            debug "  Pred $pred_part";
            debug "  Target ".query_desig($target_value);
        }

	    # Target value may be a plain scalar or undef or an object !!!

        if ( $pred_part =~ /^([^\.]+)\.(.*)/ )
        {
            my $pred_first = $1;
            my $pred_after = $2;

            debug "  Found a nested pred_part: $pred_first -> $pred_after" if $DEBUG;

            my( $proplim, $arclim2);
            if ( $pred_first =~ /^(.+?)([\{\[].+)$/ )
            {
                $pred_first = $1;
                ( $proplim, $arclim2 ) = parse_query_value($2);
                debug "Using proplim ".query_desig($proplim);
            }
            # TODO: Use alos arclim

            # It may be a method for the node class
            my $subres = $node->$pred_first($proplim, $args_in);

            unless(  UNIVERSAL::isa($subres, 'RDF::Base::List') )
            {
                unless( UNIVERSAL::isa($subres, 'ARRAY') )
                {
                    $subres = [$subres];
                }
                $subres = RDF::Base::List->new($subres);
            }

            foreach my $subnode ( $subres->nodes )
            {
                if ( $subnode->meets_proplim({$pred_after => $target_value},
                                             $args_in) )
                {
                    next PRED;  # test passed
                }
            }

            debug $node->sysdesig ." failed." if $DEBUG;
            return 0;           # test failed
        }


        # NEGATION
        if ( $pred_part eq 'not' )
        {
            if ( $node->meets_proplim( $target_value, $args_in ) )
            {
                return 0;       # test failed
            }
            else
            {
                next PRED;      # test passed
            }
        }

#        debug "ARCLIM regexp: @{[join '|', keys %RDF::Base::Arc::Lim::LIM]}";

        #                      Regexp compiles once
        unless ( $pred_part =~ m/^(rev_)?(.*?)(?:_(@{[join '|', keys %RDF::Base::Arc::Lim::LIM]}))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/xo )
        {
            $Para::Frame::REQ->result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
            unless( $pred_part )
            {
                if ( debug )
                {
                    debug "No pred_part?";
                    debug "Template: ".query_desig($proplim);
                    debug "For ".$node->sysdesig;
                }
            }
            die "wrong format in node find: $pred_part\n";
        }

        my $rev    = $1 ? 1 : 0;
        my $pred_in   = $2;
        my $arclim = $3 || $arclim_in;
        my $clean  = $4 || $args_in->{'clean'} || 0;
        my $match  = $5 || 'eq';
        my $prio   = $6;        #not used

        debug "  Match is '$match'" if $DEBUG;

        my $args =
        {
         %$args_in,
         match =>'eq',
         clean => $clean,
         arclim => $arclim,
        };


        my @preds;
        if ( $pred_in =~ s/^predor_// )
        {
            my( @prednames ) = split /_-_/, $pred_in;
#	    ( @preds ) = map RDF::Base::Pred->get($_), @prednames;
            @preds = @prednames;
        }
        else
        {
            @preds = $pred_in;
        }

#	#### ARCS
#	if( ref $node eq 'RDF::Base::Arc' )
#	{
#	    ## TODO: Handle preds in the form 'obj.scof'
#
#	    if( ($match ne 'eq' and $match ne 'begins') or $clean )
#	    {
#		confess "Not implemented: $pred_part";
#	    }
#
#	    # Failes test if arc doesn't meets the arclim
#	    return 0 unless $node->meets_arclim( $arclim );
#
#	    debug "  Node is an arc" if $DEBUG;
#	    if( ($pred eq 'obj') or ($pred eq 'value') )
#	    {
#		debug "  Pred is value" if $DEBUG;
#		my $value = $node->value; # Since it's a pred
#		next PRED if $target_value eq '*'; # match all
#		if( ref $value )
#		{
#		    if( $match eq 'eq' )
#		    {
#			next PRED # Passed test
#			  if $value->equals( $target_value, $args );
#		    }
#		    elsif( $match eq 'begins' )
#		    {
#			confess "Matchtype 'begins' only allowed for strings, not ". ref $value
#			  unless( ref $value eq 'RDF::Base::Literal::String' );
#
#			if( $value->begins( $target_value, $args ) )
#			{
#			    next PRED; # Passed test
#			}
#		    }
#		    elsif( $match eq 'exist' )
#		    {
#			debug "Checking exist, target_value: $target_value" if $DEBUG;
#			next PRED
#			  unless( $target_value ); # no props exist on the value
#		    }
#		    else
#		    {
#			confess "Matchtype not implemented: $match";
#		    }
#
#		    debug $node->sysdesig ." failed on arc value." if $DEBUG;
#		    return 0; # Failed test
#		}
#		else
#		{
#		    die "not implemented";
#		}
#	    }
#	    elsif( $pred eq 'subj' )
#	    {
#		debug "  pred is subj" if $DEBUG;
#		my $subj = $node->subj;
#		if( $subj->equals( $target_value, $args ) )
#		{
#		    next PRED; # Passed test
#		}
#		else
#		{
#		    debug $node->sysdesig ." failed." if $DEBUG;
#		    return 0; # Failed test
#		}
#	    }
#	    else
#	    {
#		debug "Asume pred '$pred' for arc is a node prop" if $DEBUG;
#	    }
#	} #### END ARCS
#	elsif( ($pred eq 'subj') or ($pred eq 'obj') )
#	{
#	    debug "QUERY ".query_desig($proplim);
#	    debug  "ON ".$node->desig;
#	    confess "Call for $pred on a nonarc ".$node->desig;
#	}

        foreach my $pred ( @preds )
        {
            if ( $pred =~ /^count_pred_(.*)/ )
            {
                $pred = $1;

                if ( $clean )
                {
                    confess "clean for count_pred not implemented";
                }

                if ( $target_value eq '*' )
                {
                    $target_value = 0;
                    $match = 'gt'; # TODO: checkthis
                }

                debug "    count pred $pred" if $DEBUG;

                my $count;
                if ( $rev )
                {
                    $count = $node->revcount($pred, $args);
                    debug "      counted $count (rev)" if $DEBUG;
                }
                else
                {
                    $count = $node->count($pred, $args);
                    debug "      counted $count" if $DEBUG;
                }

                my $matchtype =
                {
                 eq    => '==',
                 ne    => '!=',
                 gt    => '>',
                 lt    => '<',
                };

                if ( my $cmp = $matchtype->{$match} )
                {
                    unless( $target_value =~ /^\d+/ )
                    {
                        throw('action', "Target value must be a number");
                    }

                    if ( eval "$count $cmp $target_value" )
                    {
                        debug 3,"      MATCH";
                        next PRED; # test passed
                    }
                }
                else
                {
                    confess "Matchtype '$match' not implemented";
                }

            }
            elsif ( ($match eq 'eq') or
                    ($match eq 'ne') or
                    ($match eq 'lt') or
                    ($match eq 'gt')
                  )
            {
                debug "    match is $match/$rev (calling has_value)" if $DEBUG;
                next PRED       # Check next if this test pass
                  if $node->has_value({$pred=>$target_value},
                                      {
                                       %$args,
                                       rev=>$rev,
                                       match=>$match,
                                      } );
            }
            elsif ( $match eq 'exist' )
            {
                debug "    match is exist" if $DEBUG;
                if ( $rev )
                {
                    if ( $target_value ) # '1'
                    {
                        debug "Checking rev exist true" if $DEBUG;
                        next PRED
                          if ( $node->has_revpred( $pred, {}, $args ) );
                    }
                    else
                    {
                        debug "Checking rev exist false" if $DEBUG;
                        next PRED
                          unless ( $node->has_revpred( $pred, {}, $args ) );
                    }
                }
                else
                {
                    if ( $target_value ) # '1'
                    {
                        debug "Checking rel exist true (target_value: $target_value)" if $DEBUG;
                        next PRED
                          if ( $node->has_pred( $pred, {}, $args ) );
                    }
                    else
                    {
                        debug "Checking rel exist false: unless has_pred( $pred, {}, ".
                          $arclim_in->sysdesig .")" if $DEBUG;
                        next PRED
                          unless ( $node->has_pred( $pred, {}, $args ) );
                    }
                }
            }
            elsif ( ($match eq 'begins') or ($match eq 'like') )
            {
                debug "    match is $match" if $DEBUG;
                if ( $rev )
                {
                    confess "      rev not supported for matchtype $match";
                }

                next PRED       # Check next if this test pass
                  if $node->has_value({$pred=>$target_value},
                                      {
                                       %$args,
                                       match => $match,
                                      } );
            }
            else
            {
                confess "Matchtype '$match' not implemented";
            }
        }

        # This node failed the test
        debug $node->sysdesig ." failed." if $DEBUG;
        return 0;
    }

    # All properties good
    debug $node->sysdesig ." passed." if $DEBUG;
    return 1;
}


##############################################################################

=head2 add_arc

  $n->add_arc({ $pred => $value }, \%args )

Supported args are:
  res
  read_access
  write_access
  weight

Returns:

  The arc object


See also L<RDF::Base::Resource/add>

=cut

sub add_arc
{
    my( $node, $props, $args) = @_;

    if ( scalar keys %$props > 1 )
    {
        confess "add_arc only takes one prop";
    }

    my %extra;
    if ( $args->{'read_access'} )
    {
        $extra{ read_access } = $args->{'read_access'}->id;
    }
    if ( $args->{'write_access'} )
    {
        $extra{ write_access } = $args->{'write_access'}->id;
    }
    if ( $args->{'weight'} )
    {
        $extra{ arc_weight } = $args->{'weight'};
    }

    my $arc;

    foreach my $pred_name ( keys %$props )
    {
        # Must be pred_name, not pred

        # Values may be other than Resources
        my $vals = Para::Frame::List->new_any( $props->{$pred_name} );

        my @vals_array = $vals->as_array;
        if ( scalar @vals_array > 1 )
        {
            confess "add_arc only takes one value";
        }

        foreach my $val ( @vals_array )
        {
            $arc = RDF::Base::Arc->create({
                                           subj => $node,
                                           pred => $pred_name,
                                           value => $val,
                                           %extra,
                                          }, $args);
        }
    }

    return $arc;
}


##############################################################################

=head2 replace

  $n->replace( \@arclist, \%props, \%args )

See L</update> for description of what is done.

But here we explicitly check against the given list of arcs.

Adds arcs with L<RDF::Base::Arc/create> and removes arcs with
L<RDF::Base::Arc/remove>.

The C<%props> are processed by L</construct_proplist> and C<@arclist>
are processed by L</find_arcs>.

We use valclean of the value syskey for a key for what strings to
replace.

Supported args are:

  res

Debug:

  3 = detailed info
  4 = more details

Returns:

The number of arcs created or removed.

=cut

sub replace
{
    my( $node, $oldarcs, $props, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(4);

    # Determine new and old arcs

    # - existing specified arcs is unchanged
    # - nonexisting specified arcs is created
    # - existing nonspecified arcs is removed

    # Replace value where it can be done


    my( %add, %del, %del_pred );

    my $res = $args->{'res'} ||= RDF::Base::Resource::Change->new;
    my $changes_prev = $res->changes;

    $oldarcs = $node->find_arcs($oldarcs, $args);
    $props   = $node->construct_proplist($props, $args);

    debug "Normalized oldarcs ".($oldarcs->sysdesig)." and props ".query_desig($props)
      if debug > 3;

    foreach my $arc ( $oldarcs->as_array )
    {
        my $val_key = $arc->value->syskey;

        debug 3, "  old val: $val_key (".$arc->sysdesig.")";
        $del{$arc->pred->plain}{$val_key} = $arc;
    }

    # go through the new values and remove existing values from the
    # remove list and add nonexisting values to the add list

    my( $pred, $valtype );
    foreach my $pred_name ( keys %$props )
    {
        debug 3, "  pred: $pred_name ".$props->{$pred_name}->sysdesig;

        if ( $pred_name eq 'label' )
        {
            my $val = $props->{'label'}->get_first_nos;
            $node->set_label( $val );
            next;
        }

        my $pred = RDF::Base::Pred->get_by_label( $pred_name );
        my $valtype = $pred->valtype;

        foreach my $val_in ( @{$props->{$pred_name}} )
        {
            my $val  = RDF::Base::Resource->
              get_by_anything( $val_in,
                               {
                                %$args,
                                valtype => $valtype,
                               });

            my $val_key = $val->syskey;

            debug 3, "    new val: $val_key (".$val.")";

            if ( $del{$pred_name}{$val_key} )
            {
                debug 3, "    keep $val_key";
                delete $del{$pred_name}{$val_key};
            }
            elsif ( $val_key ne 'undef' )
            {
                debug 3, "    add  $val_key";
                $add{$pred_name}{$val_key} = $val;
            }
            else
            {
                debug 3, "    not add <undef>";
            }
        }
    }

    # We should prefere to replace the values for properties with
    # unique predicates. The updating of the value gives a better
    # history recording.

    # We are putting the arcs which should have its value replaced
    # in %del_pred and keeps the arc that should be removed in
    # %del

    # But the new value may also infere the old value. If the old
    # value is going to be infered, we should not replace it, but
    # rather add the new value.

    foreach my $pred_name ( keys %del )
    {
        foreach my $val_key ( keys %{$del{$pred_name}} )
        {
            my $arc = $del{$pred_name}{$val_key};
            $del_pred{$pred_name} ||= [];

            # Temporarily inserts the keys here. Replace it with the
            # arcs later
            push @{$del_pred{$pred_name}}, $val_key;
        }
    }

    # %del_pred holds a list of keys above. Below, we replaces it
    # with unique arcs.

    debug 3, "See if existing arc should be replaced";

    foreach my $pred_name (keys %del_pred)
    {
        debug 3, "  $pred_name";
        if ( @{$del_pred{$pred_name}} > 1 )
        {
            debug 3, "    had more than one arc";
            delete $del_pred{$pred_name};
        }
        else
        {
            my $val_key = $del_pred{$pred_name}[0];
            debug 3, "  Considering $pred_name val key $val_key";
            $del_pred{$pred_name} = delete $del{$pred_name}{$val_key};
        }
    }

    # By first adding new arcs, some of the arcs shedueld for
    # removal may become indirect (infered), and therefore not
    # removed

    arc_lock();

    foreach my $pred_name ( keys %add )
    {
        foreach my $key ( keys %{$add{$pred_name}} )
        {
            debug 3, "  now adding $key";
            my $value = $add{$pred_name}{$key};

            if ( $del_pred{$pred_name} )
            {
                # See if the new value is going to infere the old
                # value. Do this by first creating the new arc. And IF
                # the old arc gets infered, keep it. If not, we make
                # the new arc be a replacement of the old arc.

                my $arc = $del_pred{$pred_name};
                my $new;

                # If old arc is new, update it in place
                #
                if( $arc->is_new )
                {
                    debug "Updating value of existing new arc";
                    $new = $arc->set_value( $value, $args );

#                    debug "New arc: ".$new->sysdesig;
#                    debug "New val_in: ".datadump($value,1);
#                    debug "New val_out: ".datadump($new->value,1);
                }
                else
                {
                    $new = RDF::Base::Arc->
                      create({
                              subj        => $arc->subj->id,
                              pred        => $arc->pred->id,
                              value       => $value,
                              active      => 0, # Activate later
                             }, {
                                 %$args,
                                 ignore_card_check => 1,
                                } );

                    debug 3, "  should we replace $arc->{id}?";
                    if ( $arc->direct and $new->is_new )
                    {
                        debug 3, "    yes!";
                        $new->set_replaces( $arc, $args );
                        debug 3, $arc->sysdesig;
                    }
                    else
                    {
                        debug 3, "    no!";
                    }
                }

                if ( $args->{'activate_new_arcs'} )
                {
                    # Will deactivate replaced arc
                    $new->submit($args) unless $new->submitted;
                    $new->activate( $args ) unless $new->active;
                }

                delete $del_pred{$pred_name};
            }
            else
            {
                RDF::Base::Arc->create({
                                        subj => $node,
                                        pred => $pred_name,
                                        value => $value,
                                       }, $args );
            }
        }
    }

    foreach my $pred_name ( keys %del )
    {
        foreach my $key ( keys %{$del{$pred_name}} )
        {
            debug 3, "  now removing $key";
            $del{$pred_name}{$key}->remove( $args );
        }
    }

    foreach my $pred_name ( keys %del_pred )
    {
        debug 3, "  now removing other $pred_name";
        $del_pred{$pred_name}->remove( $args );
    }

    arc_unlock();

    debug 3, "-- done";
    return $res->changes - $changes_prev;
}


##############################################################################

=head2 revreplace

  $n->revreplace( \@arclist, \%props, \%args )

Reverse of L</replace>


=cut

sub revreplace
{
    my( $node, $oldarcs, $revprops, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my( %add, %del, %del_pred );

    my $res = $args->{'res'} ||= RDF::Base::Resource::Change->new;
    my $changes_prev = $res->changes;

    $oldarcs = $node->find_revarcs($oldarcs, $args);
    #$revprops   = $node->construct_proplist($revprops, $args);

    foreach my $arc ( $oldarcs->as_array )
    {
        my $subj_key = $arc->subj->syskey;
        $del{$arc->pred->plain}{$subj_key} = $arc;
    }

    # go through the new values and remove existing values from the
    # remove list and add nonexisting values to the add list

    my( $pred );
    foreach my $pred_name ( keys %$revprops )
    {
        my $pred = RDF::Base::Pred->get_by_label( $pred_name );
        my $vals = Para::Frame::List->new_any( $revprops->{$pred_name} );

        foreach my $subj_in ( @$vals )
        {
            my $subj  = RDF::Base::Resource->get_by_anything( $subj_in, $args );

            my $subj_key = $subj->syskey;

            if ( $del{$pred_name}{$subj_key} )
            {
                delete $del{$pred_name}{$subj_key};
            }
            elsif ( $subj_key ne 'undef' )
            {
                $add{$pred_name}{$subj_key} = $subj;
            }
        }
    }

    foreach my $pred_name ( keys %del )
    {
        foreach my $subj_key ( keys %{$del{$pred_name}} )
        {
            my $arc = $del{$pred_name}{$subj_key};
            $del_pred{$pred_name} ||= [];

            push @{$del_pred{$pred_name}}, $subj_key;
        }
    }

    foreach my $pred_name (keys %del_pred)
    {
        if ( @{$del_pred{$pred_name}} > 1 )
        {
            delete $del_pred{$pred_name};
        }
        else
        {
            my $subj_key = $del_pred{$pred_name}[0];
            $del_pred{$pred_name} = delete $del{$pred_name}{$subj_key};
        }
    }

    arc_lock();

    foreach my $pred_name ( keys %add )
    {
        foreach my $key ( keys %{$add{$pred_name}} )
        {
            my $subj = $add{$pred_name}{$key};

            if ( $del_pred{$pred_name} )
            {
                my $arc = $del_pred{$pred_name};
                my $new = RDF::Base::Arc->
                  create({
                          subj        => $subj,
                          pred        => $arc->pred->id,
                          value       => $arc->obj->id,
                          active      => 0, # Activate later
                         }, {
                             %$args,
                             ignore_card_check => 1,
                            } );

                # Allowing changed subj in versions
                #
                if ( $arc->direct and $new->is_new )
                {
                    $new->set_replaces( $arc, $args );
                }

                if ( $args->{'activate_new_arcs'} )
                {
                    $new->submit($args) unless $new->submitted;
                    $new->activate( $args ) unless $new->active;
                }

                delete $del_pred{$pred_name};
            }
            else
            {
                RDF::Base::Arc->create({
                                        subj => $subj,
                                        pred => $pred_name,
                                        value => $node,
                                       }, $args );
            }
        }
    }

    foreach my $pred_name ( keys %del )
    {
        foreach my $key ( keys %{$del{$pred_name}} )
        {
            $del{$pred_name}{$key}->remove( $args );
        }
    }

    foreach my $pred_name ( keys %del_pred )
    {
        $del_pred{$pred_name}->remove( $args );
    }

    arc_unlock();

    return $res->changes - $changes_prev;
}


##############################################################################

=head2 remove

  $n->remove( $args )

Removes the node with all arcs pointing to and from the node.

It does not do a recursive remove.  You will have to traverse the tree
by yourself.

Supported args are:
  arclim
  res
  force
  force_recursive

TODO: Count the changes correctly

Returns: The number of arcs removed

=cut

sub remove
{
    my( $node, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);
    my $changes_prev = $res->changes;

    debug "Removing resource ".$node->sysdesig;

#    if( ref $node eq 'RDF::Base::Arc' )
#    {
#	my($package, $filename, $line) = caller;
#	unless( $line == 3366 )
#	{
#	    confess "Wrong trurn";
#	}
#    }


    my $cnt = 0;
    my @arcs = ( $node->arc_list(undef, undef, $args)->nodes,
                 $node->revarc_list(undef, undef, $args)->nodes );
    foreach my $arc ( @arcs )
    {
        $arc->remove( $args ) unless $arc->implicit;

        unless( ++$cnt % 100 )
        {
            if ( $Para::Frame::REQ )
            {
                $Para::Frame::REQ->note(sprintf "Removed %6d of %6d", $cnt, $#arcs);
#		$Para::Frame::REQ->note(sprintf "PRT1:%7.3f",$::PRT1 );
#		$Para::Frame::REQ->note(sprintf "PRT2:%7.3f",$::PRT2 );
#		$Para::Frame::REQ->note(sprintf "PRT3:%7.3f",$::PRT3 );
#		$Para::Frame::REQ->note(sprintf "PRT4:%7.3f",$::PRT4 );
#		$Para::Frame::REQ->note(sprintf "PRT5:%7.3f",$::PRT5 );
#		$::PRT1 = 0;
#		$::PRT2 = 0;
#		$::PRT3 = 0;
#		$::PRT4 = 0;
#		$::PRT5 = 0;

                $Para::Frame::REQ->may_yield;
                die "cancelled" if $Para::Frame::REQ->cancelled;
            }
        }
    }

    # Remove node
    #
    if ( $node->has_node_record )
    {
        if ( $args->{'force'} or $args->{'force_recursive'} )
        {
            $RDF::dbix->delete("from node where node=?", $node->id);
            debug "  node record deleted";

            # Remove from cache
            #
            if ( my $id = $node->id )
            {
                delete $RDF::Base::Cache::Resource{ $id };
            }
        }
        else
        {
            debug "NOT REMOVING NODE RECORD";
        }
    }

    debug "Returning number ".($res->changes - $changes_prev);

    return $res->changes - $changes_prev;
}


##############################################################################

=head2 has_node_record

  $n->has_node_record

Implemented i L<RDF::Base::Resource/has_node_record>

For other nodes, like literals..:

Returns: false

=cut

sub has_node_record
{
    return 0;
}


##############################################################################

=head2 copy_props

 $n->copy_props( $from_obj, \@preds, \%args )

Copies all properties with listed C<@preds> from C<$from_obj>.

Returns:

=cut

sub copy_props
{
    my( $to_obj, $from_obj, $props, $args_in ) = @_;

    my( $args, $arclim, $res ) = parse_propargs( $args_in );
    my $R = RDF::Base->Resource;

    foreach my $pred ( @$props )
    {
        my $list = $from_obj->list( $pred, undef, $args );
        $to_obj->add({ $pred => $list }, $args )
          if ( $list );
    }
}


##############################################################################

=head2 copy_revprops

 $n->copy_revprops( $from_obj, \@preds, \%args )

Copies all rev-properties with listed C<@preds> from C<$from_obj>.

Returns:

=cut

sub copy_revprops
{
    my( $to_obj, $from_obj, $props, $args_in ) = @_;

    my( $args, $arclim, $res ) = parse_propargs( $args_in );
    my $R = RDF::Base->Resource;

    foreach my $pred ( @$props )
    {
        my $list = $from_obj->revlist( $pred, undef, $args );
        $list->add({ $pred => $to_obj }, $args )
          if ( $list );
    }
}


##############################################################################

=head2 find_arcs

  $n->find_arcs( [ @crits ], \%args )

  $n->find_arcs( $query, \%args )

NB! Use L<RDF::Base::Resource/arc_list> instead!

Used by L<RDF::Base::Node/replace>

C<@crits> can be a mixture of arcs, hashrefs or arc numbers. Hashrefs
holds pred/value pairs that is added as arcs. Mostly only usable if
called via L<RDF::Base::Node/replace>.

Returns the union of all results from each criterion

Returns: A L<RDF::Base::List> of found L<RDF::Base::Arc>s

=cut

sub find_arcs
{
    my( $node, $props, $args ) = @_;

    unless( ref $props and (ref $props eq 'ARRAY' or
                            ref $props eq 'RDF::Base::List' )
          )
    {
        $props = [$props];
    }

    my $arcs = [];

    foreach my $crit ( @$props )
    {
        if ( ref $crit and UNIVERSAL::isa($crit, 'RDF::Base::Arc') )
        {
            push @$arcs, $crit;
        }
        elsif ( ref($crit) eq 'HASH' )
        {
            foreach my $pred ( keys %$crit )
            {
                my $val = $crit->{$pred};
                my $found = $node->arc_list($pred,undef,$args)->find({value=>$val}, $args);
                push @$arcs, $found->as_array if $found->size;
            }
        }
        elsif ( $crit =~ /^\d+$/ )
        {
            push @$arcs, RDF::Base::Arc->get($crit);
        }
        else
        {
            confess "not implemented".query_desig($props);
        }
    }

    if ( debug > 3 )
    {
        debug "Finding arcs: ".query_desig($props);

        if ( @$arcs )
        {
            debug "Found values:";
        }
        else
        {
            debug "Found no values";
        }

        foreach my $arc (@$arcs)
        {
            debug "  ".$arc->sysdesig($args);
        }
    }

    return RDF::Base::Arc::List->new($arcs);
}


##############################################################################

=head2 find_revarcs

  $n->find_revarcs( [ @crits ], \%args )

  $n->find_revarcs( $query, \%args )

See L</find_arcs>

=cut

sub find_revarcs
{
    my( $node, $props, $args ) = @_;

    unless( ref $props and (ref $props eq 'ARRAY' or
                            ref $props eq 'RDF::Base::List' )
          )
    {
        $props = [$props];
    }

    my $arcs = [];

    foreach my $crit ( @$props )
    {
        if ( ref $crit and UNIVERSAL::isa($crit, 'RDF::Base::Arc') )
        {
            push @$arcs, $crit;
        }
        elsif ( ref($crit) eq 'HASH' )
        {
            foreach my $pred ( keys %$crit )
            {
                my $val = $crit->{$pred};
                my $found = $node->revarc_list($pred,undef,$args)->find({subj=>$val}, $args);
                push @$arcs, $found->as_array if $found->size;
            }
        }
        elsif ( $crit =~ /^\d+$/ )
        {
            push @$arcs, RDF::Base::Arc->get($crit);
        }
        else
        {
            confess "not implemented".query_desig($props);
        }
    }

    return RDF::Base::Arc::List->new($arcs);
}


##############################################################################

=head2 construct_proplist

  $n->construct_proplist(\%props, \%args)

Checks that the values has the right format. If a value is a hashref;
looks up an object with those properties using L</find_set>.

TODO: REMOVE THE NEED FOR THIS!

Used by L</replace>.

Returns:

the normalized hashref of props.

Exceptions:

confesses if a value is an object of an unknown class.

=cut

sub construct_proplist
{
    my( $node, $props_in, $args ) = @_;

    my $props_out = {};

#    Para::Frame::Logging->this_level(4);

    if ( debug > 2 )
    {
        debug "Normalized props ".query_desig($props_in);
        debug "With args ".query_desig($args);
    }

    foreach my $pred_name ( keys %$props_in )
    {
        # Not only objs
        my $vals = Para::Frame::List->new_any( $props_in->{$pred_name} );

        # Only those alternatives. Not other objects based on ARRAY,

        foreach my $val ( $vals->as_array )
        {
            if ( ref $val )
            {
                if ( ref $val eq 'HASH' )
                {
                    ## find_set node
                    $val = RDF::Base::Resource->find_set($val, $args);
                }
                elsif ( ref $val eq 'RDF::Base::Undef' )
                {
                    # OK
                }
                elsif ( UNIVERSAL::isa($val, 'RDF::Base::Node') )
                {
                    # OK
                }
                else
                {
                    debug query_desig($val) if debug > 2;
                    confess "Not implemented: ".ref($val);
                }
            }
            else
            {
                my $valtype;
                if ( $pred_name eq 'value' )
                {
                    $valtype = $node->this_valtype( $args );
                    $val = $valtype->instance_class->
                      parse( $val,
                             {
                              valtype => $valtype,
                             });
                }
                elsif ( $pred_name eq 'label' )
                {
                    #$valtype = RDF::Base::Constants->get('term');
                }
                else
                {
                    # Only handles pred nodes
                    $valtype = RDF::Base::Pred->get_by_label($pred_name)->valtype;
                    $val = $valtype->instance_class->
                      parse( $val,
                             {
                              %$args,
                              valtype => $valtype,
                             });
                }
            }
        }

        $props_out->{$pred_name} = $vals;
    }

    return $props_out;
}


##############################################################################

=head2 update_by_query

  $n->update_by_query( \%args )

Setts query param id to node id.

Calls L<RDF::Base::Widget::Handler/update_by_query> for the main work.

Returns: -

=cut

sub update_by_query
{
    my( $node, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);
    return RDF::Base::Widget::Handler->update_by_query({
                                                        %$args,
                                                        node => $node,
                                                       });
}


##############################################################################

=head2 add_note

  $n->add_note( $text, \%args )

Adds a C<note>

Supported args are:

  res

=cut

sub add_note
{
    my( $node, $note, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    $note =~ s/\n+$//;          # trim
    unless( length $note )
    {
        confess "No note given";
    }
    my $changes = $res->changes;
    $node->add({'note' => $note}, {%$args, activate_new_arcs=>1});

    if( $res->changes - $changes )
    {
        if ( $Para::Frame::REQ )
        {
            $Para::Frame::REQ->result_message($note);
        }
        else
        {
            debug $node->desig($args).">> $note";
        }
    }
}


#########################################################################

=head2 set_arc

Called for literal resources. Ignored here but active for literal nodes

=cut

sub set_arc
{
    return $_[1];               # return the arc
}


##############################################################################

=head2 wu_jump

  $n->wu_jump( \%attrs, \%args )

Attrs are the L<Para::Frame::Widget/jump> attributes

Special args:

  name_method

Returns: a HTML link to a form form updating the node

=cut

sub wu_jump
{
    my( $node, $attrs, $args ) = @_;

    $attrs ||= {};
    $args ||= {};

    my $label = delete($attrs->{'label'});
    unless( $label )
    {
        if( my $name_method = $args->{'name_method'} )
        {
            $label = $node->$name_method(undef,$args);
        }
    }

    $label ||= $node->desig($args);

    return Para::Frame::Widget::jump($label,
                                     $node->form_url($args),
                                     $attrs,
                                    );
}


##############################################################################

=head2 wun_jump

  $n->wun_jump( \%attrs, \%args )

Attrs are the L<Para::Frame::Widget/jump> attributes

Returns: a HTML link to node-updating page

=cut

sub wun_jump
{
    my( $node, $attrs, $args_in ) = @_;

    $attrs ||= {};
    my $base = $Para::Frame::REQ->site->home->url;
    my $url = URI->new('rb/node/update.tt')->abs($base);
    $url->query_form([id=>$node->id]);
    my $label = delete($attrs->{'label'}) || 'Node';

    return Para::Frame::Widget::jump($label, $url, $attrs);
}


##############################################################################

=head2 wp_jump

  $n->wp_jump( \%attrs, \%args )

Attrs are the L<Para::Frame::Widget/jump> attributes

Returns: a HTML link to page presenting the node

=cut

sub wp_jump
{
    return shift->wu_jump(@_);
}


#########################################################################

=head2 code_class

  $node->code_class()

List the class of the node

=cut

sub code_class
{
    my( $node ) = @_;

    return Para::Frame::Code::Class->get($node);
}


#########################################################################

=head2 wuirc_input_type

=cut

sub wuirc_input_type
{
    my( $this, $args ) = @_;

    my $alternatives = $args->{'alternatives'};
    my $is_scof = $args->{'range_scof'};
    my $range_count;

    my( $range, $range_pred ) = range_pred($args)
      or confess "Range missing ".datadump($args,1);

    my $rev_range_pred = 'rev_'.$range_pred;
    $rev_range_pred =~ s/^rev_rev_//;

    if ( $alternatives )
    {
        $range_count = $alternatives->size;
    }
    elsif ( $range_pred =~ /^rev_/ )
    {
        $range_count = $range->count($rev_range_pred);
    }
    else
    {
        $range_count = $range->revcount($range_pred);
    }

    return ( ( $range_count < 25 ) ?
             ( $is_scof ? 'select_tree' : 'select' )
             : 'text' );
}


#########################################################################

=head2 code_class_desig

  $node->code_class_desig()

Return a string naming the class of the node suitable for RDF::Base.

=cut

sub code_class_desig
{
    my( $node ) = @_;

    my $cl = Para::Frame::Code::Class->get($node);
    my $cl_name = $cl->name;
    if ( $cl_name =~ /^RDF::Base::Metaclass/ )
    {
        return join ", ", map $_->name, @{$cl->parents};
    }
    else
    {
        return $cl_name;
    }
}


#########################################################################

=head1 AUTOLOAD

  $n->$method()

  $n->$method( $proplim )

  $n->$method( $proplim, $args )

If C<$method> ends in C<_$arclim> there C<$arclim> is one of
L<RDF::Base::Arc::Lim/limflag>, the param C<$arclim> is set to that
value and the suffix removed from C<$method>. Args arclim is stored as
arclim2 and will be used for proplims. The given arclim will be used
in the arclim for the given $method.

If C<$proplim> or C<$arclim> are given, we return the result of
C<$n-E<gt>L<list|RDF::Base::Resource/list>( $proplim, $arclim )>. In
the other case, we return the result of C<$n-E<gt>L<prop|/prop>(
$proplim, $args )>.

But if C<$method> begins with C<rev_> we instead call the
corresponding L</revlist> or L</revprop> correspondingly, with the
prefix removed.

Note that the L<RDF::Base::List/AUTOLOAD> will distribute the method
calls so that C<$list-E<gt>$method> will via this C<AUTOLOAD> call each
elements C<$method> and return the new list.

=cut

AUTOLOAD
{
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;
    return if $method =~ /DESTROY$/;
    my $node = shift;
    my $class = ref($node);

    if ( $method =~ /(.*?)\.(.*)/ )
    {
#        debug "Calling ".$node->id."->$1->$2";
        return $node->$1->$2;
    }

#    warn "Calling $method\n";
    confess "AUTOLOAD $node -> $method"
      unless UNIVERSAL::isa($node, 'RDF::Base::Node');

#    # May be a way for calling methods even if the is-arc is nonactive
#    foreach my $eclass ( $node->class_list($args) )
#    {
#	if( UNIVERSAL::can($eclass,$method) )
#	{
#	    return &{"${eclass}::$method"}($node, @_);
#	}
#    }

#    die "deep recurse" if $RDF::count++ > 200;

    # Set arclim
    #
    #                Compiles this regexp only once
    if ( $method =~ s/_(@{[join '|', @{RDF::Base::Arc::Lim->names}]})$//o )
    {
        # Arclims given in this way will override param $arclim
        my( $args_in, $arclim ) = parse_propargs();
        my( $args ) = {%$args_in}; # Decouple from req default args

        $args->{'arclim2'} = $arclim;
        $args->{'arclim'} = RDF::Base::Arc::Lim->parse($1);
        $_[1] = $args;

#	debug "Setting arclim of $method to ".$args->{'arclim'}->sysdesig;
    }


    # This part is returning the corersponding value in the object
    #
    my $res =  eval
    {
	    if ( $method =~ s/^rev_?// )
	    {
            return $node->revprop($method, @_);
	    }
	    else
	    {
#            debug "Calling ".$node->id."->prop($method)";
            return $node->prop($method, @_);
	    }
    };

#    debug "Res $res err $@";


    if ( $@ )
    {
#        debug "error in: ".datadump $@;
        my $part;
        if ( $Para::Frame::REQ )
        {
            $part = $Para::Frame::REQ->result->exception;
        }
        else
        {
            $part = $@;
        }
        my $err = $part->error;
        my $desc = "";
        if ( ref $node and UNIVERSAL::isa $node, 'RDF::Base::Resource' )
        {
            foreach my $isnode ( $node->list('is')->as_array )
            {
                $desc .= sprintf("  is %s\n", $isnode->desig);
            }
        }

        if ( my $lock_level = $RDF::Base::Arc::lock_check )
        {
            $desc .= "Arc lock is in effect at level $lock_level\n";
        }
        else
        {
            $desc .= "Arc lock not in effect\n";
        }

        my $context;
        if ( $node->defined )
        {
            $context = sprintf "While calling %s for %s (%s):\n%s",
              $method, $node->id, $node->code_class_desig, $desc;
        }
        else
        {
            $context = sprintf "While calling %s for <undef>:\n%s",
              $method, $desc;
        }
        $err->text(\ $context );

        die $err;
    }
    else
    {
        return $res;
    }
}


##############################################################################


  1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::List>,
L<RDF::Base::Search>,
L<RDF::Base::Literal::Time>

=cut
