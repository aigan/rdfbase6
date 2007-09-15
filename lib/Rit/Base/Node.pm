#  $Id$  -*-cperl-*-
package Rit::Base::Node;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Node class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Node

=cut

use Carp qw( cluck confess croak carp );
use strict;
use vars qw($AUTOLOAD);
use Time::HiRes qw( time );
use LWP::Simple (); # Do not import get

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

use Rit::Base::Utils qw(valclean translate parse_query_props
			 parse_form_field_prop is_undef arc_lock
			 arc_unlock truncstring query_desig
			 convert_query_prop_for_creation
			 parse_propargs aais );


### Inherit
#
use base qw( Rit::Base::Object );

=head1 DESCRIPTION

Base class for L<Rit::Base::Resource> and L<Rit::Base::Literal>.

Inherits from L<Rit::Base::Object>.

=cut

#######################################################################

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


#######################################################################

=head2 is_node

Returns true.

=cut

sub is_node { 1 };


#######################################################################

=head2 find_remove

  $n->find_remove(\%props, \%args )

Remove matching nodes if existing.

Calls L</find> with the given props.

Calls L</remove> for each found node.

For arcs, the argument C<implicit>, if given, is passed on to
L</remove>. This will only remove arc if it no longer can be infered
and it's not explicitly declared

Supported args:

  arclim
  res
  implicit

Returns: ---

=cut

sub find_remove
{
    my( $this, $props, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    foreach my $node ( $this->find( $props, $args )->nodes )
    {
	$node->remove( $args );
    }
}


#######################################################################

=head2 id_alfanum

  $n->id_alfanum

The unique node id expressed with [0-9A-Z] as a plain string, with a
one char checksum at the end.

=cut

sub id_alfanum
{
    my $id = $_[0]->{'id'};
    my $str = "";
    my @map = ((0..9),('A'..'Z'));
    my $len = scalar(@map);
    my $chksum = 0;
    while( $id > 0 )
    {
	my $rest = $id % $len;
	$id = int( $id / $len );

	$str .= $map[$rest];
	$chksum += $rest;
    }

    return reverse($str) . $map[$chksum % $len];
}


#######################################################################

=head2 prop

  $n->prop( $predname, undef, \%args )

  $n->prop( $predname, $proplim, \%args )

  $n->prop( $predname, $value, \%args )

Returns the values of the property with predicate C<$predname>.  See
L</list> for explanation of the params.

For special predname C<id>, returns the id.

Use L</first_prop> or L</list> instead if that's what you want!

If given a value instead of a proplim, returns true/false based on if
the node has a property with the specified $predname and $value.

Returns:

If more then one node found, returns a L<Rit::Base::List>.

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

    debug 3, "!!! get ".$node->id."-> $name";

    confess "loc is a reserved dynamic property" if $name eq 'loc';
    confess "This node is not an arc" if $name eq 'subj';

    my $values = $node->list($name, @_);

    unless( $values )
    {
	return is_undef;
    }

    if( $values->size > 1 ) # More than one element
    {
	return $values;  # Returns list
    }
    elsif( $values->size ) # Return Resource, or undef if no such element
    {
	return $values->get_first_nos;
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

=head2 revprop

  $n->revprop( $predname )

  $n->revprop( $predname, $proplim )

  $n->revprop( $predname, $proplim, \%args )

Returns the values of the reverse property with predicate
C<$predname>.  See L</list> for explanation of the params.

Returns:

If more then one node found, returns a L<Rit::Base::List>.

If one node found, returns the node.

In no nodes found, returns C<undef>.

=cut

sub revprop
{
    my $node = shift;
    my $name = shift;

    $name or confess "No name param given";

    my $values = $node->revlist($name, @_);

    if( $values->size > 1 ) # More than one element
    {
	return $values;  # Returns list
    }
    elsif( $values->size ) # Return Resource, or undef if no such element
    {
	return $values->get_first_nos;
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

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

    if( $node->list(@_)->size )
    {
	return $node;
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

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

    if( $node->revlist(@_)->size )
    {
	return $node;
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

=head2 meets_proplim

  $n->meets_proplim( $proplim, \%args )

See L<Rit::Base::List/find> for docs.

This also implements meets_proplim for arcs!!!

Returns: boolean

=cut

sub meets_proplim
{
    my( $node, $proplim, $args_in_in ) = @_;
    my( $args_in, $arclim_in ) = parse_propargs($args_in_in);


#    Para::Frame::Logging->this_level(4);
    my $DEBUG = Para::Frame::Logging->at_level(3);

    if( $DEBUG )
    {
	debug "Node ".$node->sysdesig;
	debug "Arclim ".$arclim_in->sysdesig;
    }

  PRED:
    foreach my $pred_part ( keys %$proplim )
    {
	my $target_value =  $proplim->{$pred_part};
	if( $DEBUG )
	{
	    debug "  Pred $pred_part";
	    debug "  Target $target_value (".ref($target_value).")";
	}

	    # Target value may be a plain scalar or undef or an object !!!

	if( $pred_part =~ /^(\w+)\.(.*)/ )
	{
	    my $pred_first = $1;
	    my $pred_after = $2;

	    debug "  Found a nested pred_part: $pred_first -> $pred_after" if $DEBUG;

	    # It may be a method for the node class
	    my $subres = $node->$pred_first(undef, $args_in);

	    unless(  UNIVERSAL::isa($subres, 'Rit::Base::List') )
	    {
		unless( UNIVERSAL::isa($subres, 'ARRAY') )
		{
		    $subres = [$subres];
		}
		$subres = Rit::Base::List->new($subres);
	    }

	    foreach my $subnode ( $subres->nodes )
	    {
		if( $subnode->meets_proplim({$pred_after => $target_value},
					    $args_in) )
		{
		    next PRED; # test passed
		}
	    }

	    return 0; # test failed
	}


	#                      Regexp compiles once
	unless( $pred_part =~ m/^(rev_)?(\w+?)(?:_(@{[join '|', keys %Rit::Base::Arc::LIM]}))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/xo )
	{
	    $Para::Frame::REQ->result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	    unless( $pred_part )
	    {
		if( debug )
		{
		    debug "No pred_part?";
		    debug "Template: ".query_desig($proplim);
		    debug "For node ".$node->sysdesig;
		}
	    }
	    die "wrong format in find: $pred_part\n";
	}

	my $rev    = $1;
	my $pred   = $2;
	my $arclim = $3 || $arclim_in;
	my $clean  = $4 || $args_in->{'clean'} || 0;
	my $match  = $5 || 'eq';
	my $prio   = $6; #not used

	my $args =
	{
	 %$args_in,
	 match =>'eq',
	 clean => $clean,
	 arclim => $arclim,
	};


	if( $pred =~ s/^predor_// )
	{
	    my( @prednames ) = split /_-_/, $pred;
	    my( @preds ) = map Rit::Base::Pred->get($_), @prednames;
	    $pred = \@preds;
	}

	#### ARCS
	if( ref $node eq 'Rit::Base::Arc' )
	{
	    ## TODO: Handle preds in the form 'obj.scof'

	    if( ($match ne 'eq' and $match ne 'begins') or $clean )
	    {
		confess "Not implemented: $pred_part";
	    }

	    # Failes test if arc doesn't meets the arclim
	    return 0 unless $node->meets_arclim( $arclim );

	    debug "  Node is an arc" if $DEBUG;
	    if( ($pred eq 'obj') or ($pred eq 'value') )
	    {
		debug "  Pred is value" if $DEBUG;
		my $value = $node->value; # Since it's a pred
		next PRED if $target_value eq '*'; # match all
		if( ref $value )
		{
		    if( $match eq 'eq' )
		    {
			next PRED # Passed test
			  if $value->equals( $target_value, $args );
		    }
		    elsif( $match eq 'begins' )
		    {
			confess "Matchtype 'begins' only allowed for strings, not ". ref $value
			  unless( ref $value eq 'Rit::Base::Literal::String' );

			if( $value->begins( $target_value, $args ) )
			{
			    next PRED; # Passed test
			}
		    }
		    else
		    {
			confess "Matchtype not implemented: $match";
		    }

		    return 0; # Failed test
		}
		else
		{
		    die "not implemented";
		}
	    }
	    elsif( $pred eq 'subj' )
	    {
		debug "  pred is subj" if $DEBUG;
		my $subj = $node->subj;
		if( $subj->equals( $target_value, $args ) )
		{
		    next PRED; # Passed test
		}
		else
		{
		    return 0; # Failed test
		}
	    }
	    else
	    {
		debug "Asume pred '$pred' for arc is a node prop" if $DEBUG;
	    }
	} #### END ARCS
	elsif( ($pred eq 'subj') or ($pred eq 'obj') )
	{
	    debug "QUERY ".query_desig($proplim);
	    debug  "ON ".$node->desig;
	    confess "Call for $pred on a nonarc ".$node->desig;
	}


	if( $pred =~ /^count_pred_(.*)/ )
	{
	    $pred = $1;

	    if( $clean )
	    {
		confess "clean for count_pred not implemented";
	    }

	    if( $target_value eq '*' )
	    {
		$target_value = 0;
		$match = 'gt'; # TODO: checkthis
	    }

	    debug "    count pred $pred" if $DEBUG;

	    my $count;
	    if( $rev )
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

	    if( my $cmp = $matchtype->{$match} )
	    {
		unless( $target_value =~ /^\d+/ )
		{
		    throw('action', "Target value must be a number");
		}

		if( eval "$count $cmp $target_value" )
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
	elsif( $match eq 'eq' )
	{
	    debug "    match is eq" if $DEBUG;
	    if( $rev )
	    {
		debug "      (rev)\n" if $DEBUG;
		# clean not sane in rev props
		next PRED # Check next if this test pass
		  if $target_value->has_value({$pred=>$node}, $args );
	    }
	    else
	    {
#		debug "  ===> See if ".$node->desig." has $pred ".query_desig($target_value);
		next PRED # Check next if this test pass
		  if $node->has_value({$pred=>$target_value}, $args );
	    }
	}
	elsif( $match eq 'ne' )
	{
	    debug "    match is ne" if $DEBUG;
	    if( $rev )
	    {
		debug "      (rev)" if $DEBUG;
		# clean not sane in rev props
		next PRED # Check next if this test pass
		  unless $target_value->has_value({$pred=>$node}, $args );
	    }
	    else
	    {
		# Matchtype is 'eq'. Result is negated here

		next PRED # Check next if this test pass
		  unless $node->has_value({$pred=>$target_value}, $args );
	    }
	}
	elsif( $match eq 'exist' )
	{
	    debug "    match is exist" if $DEBUG;
	    if( $rev )
	    {
		if( $target_value ) # '1'
		{
		    debug "Checking rev exist true" if $DEBUG;
		    next PRED
		      if( $node->has_revpred( $pred, {}, $args ) );
		}
		else
		{
		    debug "Checking rev exist false" if $DEBUG;
		    next PRED
		      unless( $node->has_revpred( $pred, {}, $args ) );
		}
	    }
	    else
	    {
		if( $target_value ) # '1'
		{
		    debug "Checking rel exist true (target_value: $target_value)" if $DEBUG;
		    next PRED
		      if( $node->has_pred( $pred, {}, $args ) );
		}
		else
		{
		    debug "Checking rel exist false" if $DEBUG;
		    next PRED
		      unless( $node->has_pred( $pred, {}, $args ) );
		}
	    }
	}
	elsif( ($match eq 'begins') or ($match eq 'like') )
	{
	    debug "    match is $match" if $DEBUG;
	    if( $rev )
	    {
		confess "      rev not supported for matchtype $match";
	    }

	    next PRED # Check next if this test pass
	      if $node->has_value({$pred=>$target_value}, $args );
	}
	else
	{
	    confess "Matchtype '$match' not implemented";
	}

	# This node failed the test
	return 0;
    }

    # All properties good
    return 1;
}


#######################################################################

=head2 add_arc

  $n->add_arc({ $pred => $value }, \%args )

Supported args are:
  res

Returns:

  The arc object

=cut

sub add_arc
{
    my( $node, $props, $args) = @_;

    if( scalar keys %$props > 1 )
    {
	confess "add_arc only takes one prop";
    }

    my $arc;

    foreach my $pred_name ( keys %$props )
    {
	# Must be pred_name, not pred

	# Values may be other than Resources
	my $vals = Para::Frame::List->new_any( $props->{$pred_name} );

	my @vals_array = $vals->as_array;
	if( scalar @vals_array > 1 )
	{
	    confess "add_arc only takes one value";
	}

	foreach my $val ( @vals_array )
	{
	    $arc = Rit::Base::Arc->create({
		subj => $node,
		pred => $pred_name,
		value => $val,
	    }, $args);
	  }
    }

    return $arc;
}


#######################################################################

=head2 replace

  $n->replace( \@arclist, \%props, \%args )

See L</update> for description of what is done.

But here we explicitly check against the given list of arcs.

Adds arcs with L<Rit::Base::Arc/create> and removes arcs with
L<Rit::Base::Arc/remove>.

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

    # Determine new and old arcs

    # - existing specified arcs is unchanged
    # - nonexisting specified arcs is created
    # - existing nonspecified arcs is removed

    # Replace value where it can be done

#    Para::Frame::Logging->this_level(3);


    my( %add, %del, %del_pred );

    my $res = $args->{'res'} ||= Rit::Base::Resource::Change->new;
    my $changes_prev = $res->changes;

    $oldarcs = $node->find_arcs($oldarcs, $args);
    $props   = $node->construct_proplist($props, $args);

    debug "Normalized oldarcs ".($oldarcs->sysdesig)." and props ".query_desig($props)
      if debug > 3;

    foreach my $arc ( $oldarcs->as_array )
    {
#	my $val_str = valclean( $arc->value->syskey );
	my $val_str = $arc->value->syskey;

	debug 3, "  old val: $val_str (".$arc->sysdesig.")";
	$del{$arc->pred->plain}{$val_str} = $arc;
    }

    # go through the new values and remove existing values from the
    # remove list and add nonexisting values to the add list

    foreach my $pred_name ( keys %$props )
    {
	debug 3, "  pred: $pred_name";
	my $pred = Rit::Base::Pred->get_by_label( $pred_name );

	my $valtype;
	my $coltype = $pred->coltype;
	if( $coltype eq 'value' )
	{
	    # Should only replace an existing value property
	    my $varc = $node->first_arc('value', undef, $args );
	    unless( $varc )
	    {
		confess "Node $node->{id} has no existing value arc to replace";
	    }

	    $valtype = $varc->valtype;
	}
	else
	{
	    $valtype = $pred->valtype;
	}

	foreach my $val_in ( @{$props->{$pred_name}} )
	{
	    my $val  = Rit::Base::Resource->
	      get_by_anything( $val_in,
			       {
				%$args,
				valtype => $valtype,
			       });

#	    my $val_str = valclean( $val->syskey );
	    my $val_str = $val->syskey;

	    debug 3, "    new val: '$val_str' (".$val.")";

	    if( $del{$pred_name}{$val_str} )
	    {
		debug 3, "    keep $val_str";
		delete $del{$pred_name}{$val_str};
	    }
	    elsif( defined $val_str )
	    {
		debug 3, "    add  '$val_str'";
		$add{$pred_name}{$val_str} = $val;
	    }
	    else
	    {
		debug 3, "    not add <undef>";
	    }
	}
    }

    # We should prefere to replace the values for properties
    # with unique predicates. This is a must for value arcs,
    # since removing value arcs are treated as a special case.
    # The updating of the value also gives a better history
    # recording.

    # We are putting the arcs which should have its value replaced
    # in %del_pred and keeps the arc that should be removed in
    # %del

    # But the new value may also infere the old value. If the old
    # value is going to be infered, we should not replace it, but
    # rather add the new value.

    foreach my $pred_name ( keys %del )
    {
	foreach my $arc_key ( keys %{$del{$pred_name}} )
	{
	    my $arc = $del{$pred_name}{$arc_key};
	    $del_pred{$pred_name} ||= [];
	    push @{$del_pred{$pred_name}}, $arc_key;
	}
    }

    # %del_pred holds a list of keys above. Below, we replaces it
    # with unique arcs.

    debug 3, "See if existing arc should be replaced";

    foreach my $pred_name (keys %del_pred)
    {
	debug 3, "  $pred_name";
	if( @{$del_pred{$pred_name}} > 1 )
	{
	    debug 3, "    had more than one arc";
	    delete $del_pred{$pred_name};
	}
	else
	{
	    my $arc_key = $del_pred{$pred_name}[0];
	    debug 3, "  Considering $pred_name arc $arc_key";
	    $del_pred{$pred_name} = delete $del{$pred_name}{$arc_key};
	}
    }

    # By first adding new arcs, some of the arcs shedueld for
    # removal may become indirect (infered), and therefore not
    # removed

    foreach my $pred_name ( keys %add )
    {
	foreach my $key ( keys %{$add{$pred_name}} )
	{
	    debug 3, "  now adding $key";
	    my $value = $add{$pred_name}{$key};

	    if( $del_pred{$pred_name} )
	    {
		# See if the new value is going to infere the old
		# value. Do this by first creating the new arc. And IF
		# the old arc gets infered, keep it. If not, we make
		# the new arc be a replacement of the old arc.

		my $arc = $del_pred{$pred_name};


		my $new = Rit::Base::Arc->
		  create({
			  subj        => $arc->subj->id,
			  pred        => $arc->pred->id,
			  value       => $value,
			  active      => 0, # Activate later
			 }, $args );


		debug 3, "  should we replace $arc->{id}?";
		if( $arc->direct )
		{
		    debug 3, "    yes!";
		    $new->set_replaces( $arc, $args );
		}
		else
		{
		    debug 3, "    no!";
		}

		if( $args->{'activate_new_arcs'} )
		{
		    # Will deactivate replaced arc
		    $new->submit($args) unless $new->submitted;
		    $new->activate( $args );
		}

		delete $del_pred{$pred_name};
	    }
	    else
	    {
		Rit::Base::Arc->create({
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

    debug 3, "-- done";
    return $res->changes - $changes_prev;
}


#######################################################################

=head2 remove

  $n->remove( $args )

Removes the node with all arcs pointing to and from the node.

It does not do a recursive remove.  You will have to traverse the tree
by yourself.

Supported args are:
  arclim
  res

TODO: Count the changes correctly

Returns: The number of arcs removed

=cut

sub remove
{
    my( $node, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);
    my $changes_prev = $res->changes;

    debug "Removing resource ".$node->sysdesig;

    # Remove value arcs before the corresponding datatype arc
    my( @arcs, $value_arc );
    my $pred_value_id = Rit::Base::Pred->get_by_label('value')->id;

    foreach my $arc ( $node->arc_list(undef, undef, $args)->nodes )
    {
	if( $arc->pred->id == $pred_value_id )
	{
	    $value_arc = $arc;
	}
	else
	{
	    push @arcs, $arc;
	}
    }

    # Place it first
    unshift @arcs, $value_arc if $value_arc;


    foreach my $arc ( @arcs, $node->revarc_list(undef, undef, $args)->nodes )
    {
	$arc->remove( $args );
    }

    # Remove from cache
    #
    delete $Rit::Base::Cache::Resource{ $node->id };

    return $res->changes - $changes_prev;
}


#######################################################################

=head2 copy_props

 $n->copy_props( $from_obj, \@preds, \%args )

Copies all properties with listed C<@preds> from C<$from_obj>.

Returns:

=cut

sub copy_props
{
    my( $to_obj, $from_obj, $props, $args_in ) = @_;

    my( $args, $arclim, $res ) = parse_propargs( $args_in );
    my $R = Rit::Base->Resource;

    foreach my $pred ( @$props )
    {
	my $list = $from_obj->list( $pred, undef, $args );
	$to_obj->add({ $pred => $list }, $args )
	  if( $list );
    }
}


#######################################################################

=head2 copy_revprops

 $n->copy_revprops( $from_obj, \@preds, \%args )

Copies all rev-properties with listed C<@preds> from C<$from_obj>.

Returns:

=cut

sub copy_revprops
{
    my( $to_obj, $from_obj, $props, $args_in ) = @_;

    my( $args, $arclim, $res ) = parse_propargs( $args_in );
    my $R = Rit::Base->Resource;

    foreach my $pred ( @$props )
    {
	my $list = $from_obj->revlist( $pred, undef, $args );
	$list->add({ $pred => $to_obj }, $args )
	  if( $list );
    }
}


#######################################################################

=head2 find_arcs

  $n->find_arcs( [ @crits ], \%args )

  $n->find_arcs( $query, \%args )

C<@crits> can be a mixture of arcs, hashrefs or arc numbers. Hashrefs
holds pred/value pairs that is added as arcs.

Returns: A L<Rit::Base::List> of found L<Rit::Base::Arc>s

=cut

sub find_arcs
{
    my( $node, $props, $args ) = @_;

    # Returns the union of all results from each criterion

    unless( ref $props and (ref $props eq 'ARRAY' or
			   ref $props eq 'Rit::Base::List' )
	  )
    {
	$props = [$props];
    }

    my $arcs = [];

    foreach my $crit ( @$props )
    {
	if( ref $crit and UNIVERSAL::isa($crit, 'Rit::Base::Arc') )
	{
	    push @$arcs, $crit;
	}
	elsif( ref($crit) eq 'HASH' )
	{
	    foreach my $pred ( keys %$crit )
	    {
		my $val = $crit->{$pred};
		my $found = $node->arc_list($pred,undef,$args)->find({value=>$val}, $args);
		push @$arcs, $found->as_array if $found->size;
	    }
	}
	elsif( $crit =~ /^\d+$/ )
	{
	    push @$arcs, Rit::Base::Arc->get($crit);
	}
	else
	{
	    die "not implemented".query_desig($props);
	}
    }

    if( debug > 3 )
    {
	debug "Finding arcs: ".query_desig($props);

	if( @$arcs )
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

    return Rit::Base::List->new($arcs);
}


#######################################################################

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

    foreach my $pred_name ( keys %$props_in )
    {
	# Not only objs
	my $vals = Para::Frame::List->new_any( $props_in->{$pred_name} );

	# Only those alternatives. Not other objects based on ARRAY,

	foreach my $val ( $vals->as_array )
	{
	    if( ref $val )
	    {
		if( ref $val eq 'HASH' )
		{
		    ## find_set node
		    $val = Rit::Base::Resource->find_set($val, $args);
		}
		elsif( ref $val eq 'Rit::Base::Undef' )
		{
		    # OK
		}
		elsif( UNIVERSAL::isa($val, 'Rit::Base::Node') )
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
		$val = Rit::Base::Pred->get_by_label($pred_name)->valtype->instance_class->new( $val );
#		$val = Rit::Base::Literal->new( $val );
	    }
	}

	$props_out->{$pred_name} = $vals;
    }

    return $props_out;
}


#######################################################################

=head2 update_by_query

  $n->update_by_query( \%args )

Setts query param id to node id.

Calls L<Rit::Base::Widget::Handler/update_by_query> for the main work.

Returns: the number of changes done

=cut

sub update_by_query
{
    my( $node, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $id = $node->id;
    my $q = $Para::Frame::REQ->q;
    $q->param('id', $id); # Just in case...

    return Rit::Base::Widget::Handler->update_by_query({
							%$args,
							node => $node,
						       });
}


#######################################################################

=head2 add_note

  $n->add_note( $text, \%args )

Adds a C<note>

Supported args are:

  res

=cut

sub add_note
{
    my( $node, $note, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    $note =~ s/\n+$//; # trim
    unless( length $note )
    {
	confess "No note given";
    }
    debug $node->desig($args).">> $note";
    $node->add({'note' => $note}, {%$args, activate_new_arcs=>1});
}


#######################################################################

=head2 wu_jump

  $n->wu_jump( \%args )

Returns: a HTML link to a form form updating the node

=cut

sub wu_jump
{
    my( $node, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $label = $args->{'label'} || $node->desig;

    return Para::Frame::Widget::jump($label,
				     $node->form_url($args_in));
}


#######################################################################

=head2 wun_jump

  $n->wun_jump( \%args )

Returns: a HTML link to node-updating page

=cut

sub wun_jump
{
    my( $node, $args_in ) = @_;

    my $base = $Para::Frame::REQ->site->home->url;
    my $url = URI->new('rb/node/update.tt')->abs($base);
    $url->query_form([id=>$node->id]);

    return Para::Frame::Widget::jump('Node', $url);
}


#########################################################################

=head1 AUTOLOAD

  $n->$method()

  $n->$method( $proplim )

  $n->$method( $proplim, $args )

If C<$method> ends in C<_$arclim> there C<$arclim> is one of
L<Rit::Base::Arc::Lim/limflag>, the param C<$arclim> is set to that value
and the suffix removed from C<$method>.

If C<$proplim> or C<$arclim> are given, we return the result of
C<$n-E<gt>L<list|/list>( $proplim, $arclim )>. In the other case, we return the
result of C<$n-E<gt>L<prop|/prop>( $proplim, $args )>.

But if C<$method> begins with C<rev_> we instead call the
corresponding L</revlist> or L</revprop> correspondingly, with the
prefix removed.

Note that the L<Rit::Base::List/AUTOLOAD> will distribute the method
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

#    warn "Calling $method\n";
    confess "AUTOLOAD $node -> $method"
      unless UNIVERSAL::isa($node, 'Rit::Base::Node');

#    # May be a way for calling methods even if the is-arc is nonactive
#    foreach my $eclass ( $node->class_list($args) )
#    {
#	if( UNIVERSAL::can($eclass,$method) )
#	{
#	    return &{"${eclass}::$method"}($node, @_);
#	}
#    }

#    die "deep recurse" if $Rit::count++ > 200;

    # Set arclim
    #
    #                Compiles this regexp only once
    if( $method =~ s/_(@{[join '|', Rit::Base::Arc::Lim->names]})$//o )
    {
	# Arclims given in this way will override param $arclim
	$_[1] = $1;
    }


    # This part is returning the corersponding value in the object
    #
    my $res =  eval
    {
	if( $method =~ s/^rev_?// )
	{
	    return $node->revprop($method, @_);

#	    if( @_ )
#	    {
#		return $node->revlist($method, @_);
#	    }
#	    else
#	    {
#		return $node->revprop($method);
#	    }
	}
	else
	{
	    return $node->prop($method, @_);

#	    if( @_ )
#	    {
#		return $node->list($method, @_);
#	    }
#	    else
#	    {
#		return $node->prop($method);
#	    }
	}
    };

#    debug "Res $res err $@";


    if( $@ )
    {
	my $err;
	if( $Para::Frame::REQ )
	{
	    $err = $Para::Frame::REQ->result->exception;
	}
	else
	{
	    $err = $@;
	}
	debug datadump $err;
	my $desc = "";
	if( ref $node and UNIVERSAL::isa $node, 'Rit::Base::Resource' )
	{
	    foreach my $isnode ( $node->list('is')->as_array )
	    {
		$desc .= sprintf("  is %s\n", $isnode->desig);
	    }
	}

	if( my $lock_level = $Rit::Base::Arc::lock_check )
	{
	    $desc .= "Arc lock is in effect at level $lock_level\n";
	}
	else
	{
	    $desc .= "Arc lock not in effect\n";
	}

	if( $node->defined )
	{
	    confess sprintf "While calling %s for %s (%s):\n%s\n%s",
	      $method, $node->sysdesig, $node->code_class_desig, $desc, $err;
	}
	else
	{
	    confess sprintf "While calling %s for <undef>:\n%s\n%s",
	      $method, $desc, $err;
	}
    }
    else
    {
	return $res;
    }
}


#######################################################################


1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>,
L<Rit::Base::Literal::Time>

=cut
