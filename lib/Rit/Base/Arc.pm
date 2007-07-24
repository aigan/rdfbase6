#  $Id$  -*-cperl-*-
package Rit::Base::Arc;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource Arc class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Arc

=cut

use utf8;

use Carp qw( cluck confess carp croak shortmess );
use strict;
use Time::HiRes qw( time );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";

    $Rit::Base::Arc = 0; # Internal object enumeration
}

use Para::Frame::Utils qw( throw debug datadump package_to_module );
use Para::Frame::Reload;

use Rit::Base::Time qw( now );
use Rit::Base::List;
use Rit::Base::Pred;
use Rit::Base::Literal;
use Rit::Base::String;
use Rit::Base::Rule;
use Rit::Base::Constants qw( $C_ritguides $C_public $C_sysadmin_group $C_value );

use Rit::Base::Utils qw( cache_update getpred valclean translate
                         is_undef truncstring send_cache_update
                         query_desig parse_propargs );

### Inherit
#
use base qw( Rit::Base::Resource );

# TODO:
# Move from implicit to explicit then updating implicit properties
# explicitly

# This will make "if($arc)" false if the arc is 'removed'
#
use overload 'bool' => sub{ ref $_[0] and $_[0]->subj };
use overload 'cmp'  => sub{0};
use overload 'ne'   => sub{1};
use overload 'eq'   => sub{0}; # Use method ->equals()

=head1 DESCRIPTION

Represents arcs.

Inherits from L<Rit::Base::Resource>.

=cut

# NOTE:
# $arc->{'id'}        == $rec->{'ver'}
# $arc->{'common_id'} == $rec->{'id'}

#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any pred object.

=cut

#######################################################################

=head2 create

  Rit::Base::Arc->create( \%props, \%args )

Creates a new arc and stores in in the DB.

The props:

  id : If undefined, gets a new id from the C<node_deq>

  subj : Anything that L<Rit::Base::Resource/get> takes

  subj_id : Same as C<subj>

  pred : Anything that L<Rit::Base::Resource/get> takes, called as
  L<Rit::Base::Pred>

  pred_id : Same as C<pred>

  implicit : Makes the arc both C<implicit> and C<indirect>

  obj_id : The id of the obj as a plain integer

  value : May be L<Rit::Base::Undef>, any L<Rit::Base::Literal> or a
  L<Rit::Base::Resource>

  obj : Same as L<value>

If value is a plain string, it's converted to an object based on L<Rit::Base::Pred/coltype>.

C<subj>, C<pred> and C<value> must be given.

A check is made for not creating an arc that already exists.

We do not allow arcs where subj and obj is the same resouce. (This
check may catch bad cyclic recursive arc inferences.)

Inferences from the new arc weill be done directly or after
L</unlock>.

Returns: The arc object

=cut

sub create
{
    my( $this, $props, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $req = $Para::Frame::REQ;
    my $dbix = $Rit::dbix;

    # Start at level 3...
    my $DEBUG = debug();
#    $DEBUG and $DEBUG --; $DEBUG and $DEBUG --;

    debug "About to create arc with props:\n".query_desig($props) if $DEBUG;

    my( @fields, @values );

    my $rec = {};

    ##################### common_id == id
    if( $props->{'common_id'} ) # used in block EXISTING
    {
	$rec->{'id'}  = $props->{'common_id'};
    }
    else
    {
	$rec->{'id'}  = $dbix->get_nextval('node_seq');
    }
    push @fields, 'id';
    push @values, $rec->{'id'};


    ##################### id == ver
    if( $props->{'id'} )
    {
	$rec->{'ver'}  = $props->{'id'};
    }
    else
    {
	$rec->{'ver'}  = $dbix->get_nextval('node_seq');
    }
    push @fields, 'ver';
    push @values, $rec->{'ver'};


    ##################### replaces_id
    if( $props->{'replaces_id'} )
    {
	$rec->{'replaces'}  = $props->{'replaces_id'};
	push @fields, 'replaces';
	push @values, $rec->{'replaces'};
    }


    ##################### source
    if( $props->{'source'} )
    {
	$rec->{'source'}  = $props->{'source'};
    }
    else
    {
	$rec->{'source'}  = $C_ritguides->id;
    }
    push @fields, 'source';
    push @values, $rec->{'source'};


    ##################### active
    push @fields, 'active';
    unless( defined $props->{'active'} )
    {
	$props->{'active'} = 0;
    }

    if( $props->{'active'} )
    {
	$rec->{'active'} = 1;
	push @values, 't';
    }
    else
    {
	$rec->{'active'} = 0;
	push @values, 'f';
    }


    ##################### submitted
    push @fields, 'submitted';
    if( $props->{'submitted'} )
    {
	if( $rec->{'active'} )
	{
	    confess "Arc can't be both active and submitted: ".query_desig($props);
	}

	$rec->{'submitted'} = 1;
	push @values, 't';
    }
    else
    {
	$rec->{'submitted'} = 0;
	push @values, 'f';
    }


    ##################### read_access
    if( $props->{'read_access'} )
    {
	$rec->{'read_access'}  = $props->{'read_access'};
    }
    else
    {
	$rec->{'read_access'}  = $C_public->id;
    }
    push @fields, 'read_access';
    push @values, $rec->{'read_access'};


    ##################### write_access
    if( $props->{'write_access'} )
    {
	$rec->{'write_access'}  = $props->{'write_access'};
    }
    else
    {
	$rec->{'write_access'}  = $C_sysadmin_group->id;
    }
    push @fields, 'write_access';
    push @values, $rec->{'write_access'};


    ##################### subj_id
    my $subj;
    if( my $subj_label = $props->{'subj_id'} || $props->{'subj'} )
    {
	$subj = Rit::Base::Resource->get( $subj_label )
	    or die "No node '$subj_label' found";
    }
    else
    {
	confess "Subj missing\n";
    }
    $rec->{'subj'} = $subj->id or confess "id missing".datadump($props, 2);
    push @fields, 'subj';
    push @values, $rec->{'subj'};


    ##################### pred_id
    my $pred = Rit::Base::Pred->get( $props->{'pred_id'} ||
					     $props->{'pred'} );
    $pred or die "Pred missing";
    my $pred_id = $pred->id;

    my $pred_name = $pred->plain;
#    warn "PRED NAME: $pred_name\n";

    $rec->{'pred'} = $pred_id;

    push @fields, 'pred';
    push @values, $rec->{'pred'};


    ##################### valtype
    if( defined $props->{'valtype'} )
    {
	if( $props->{'valtype'} )
	{
	    $rec->{'valtype'} =
	      Rit::Base::Resource->get( $props->{'valtype'} )->id;
	}
	else
	{
	    $rec->{'valtype'} = 0; # Special valtype for REMOVAL arc
	}
    }
    else
    {
	if( $pred->{'coltype'} == 6 )  # Value resource?
	{
	    ### Get valtype from subjs revarc
	    my $revarc = $subj->revarc(undef,undef,$args) # Should be only one on a value resource
	      or confess("Couldn't get revarc for value resource: ". $subj->sysdesig);

	    my $revpred = $revarc->pred;
	    $rec->{'valtype'} = $revpred->valtype->id;

	    debug("Setting valtype to ". $rec->{'valtype'} ." for value from revpred ".
		  $revpred->plain);

	    confess("I won't make a value resource with a resource as value.")
	      if( $props->{'obj_id'} );
	}
	else
	{
	    $rec->{'valtype'} = $pred->valtype->id;
	    debug("Setting valtype to ". $rec->{'valtype'} ." from pred ".
		  $pred->plain);
	}
    }

    confess("Missing valtype")
      unless( defined $rec->{'valtype'} );

    push @fields, 'valtype';
    push @values, $rec->{'valtype'};



    ##################### updated_by
    if( $req->user )
    {
	$rec->{'created_by'} = $req->user->id;
	push @fields, 'created_by';
	push @values, $rec->{'created_by'};
    }

   ##################### updated
    $rec->{'updated'} = now();
    push @fields, 'updated';
    push @values, $dbix->format_datetime($rec->{'updated'});

    $rec->{'created'} = $rec->{'updated'};
    push @fields, 'created';
    push @values, $dbix->format_datetime($rec->{'created'});


    ##################### implicit
    push @fields, 'indirect', 'implicit';
    if( $props->{'implicit'} )
    {
	$rec->{'implicit'} = 1;
	$rec->{'indirect'} = 1;

	push @values, 't', 't';
    }
    else
    {
	$rec->{'implicit'} = 0;
	$rec->{'indirect'} = 0;

	push @values, 'f', 'f';
    }


    ##################### obj thingy
    my $value;
    my $value_obj;
    # Find out the *real* coltype
    # (This gives coltype 'obj' for valtype 0 (used for REMOVAL))
    my $coltype = $Rit::Base::COLTYPE_valtype2name{ $rec->{'valtype'} } || 'obj';

    debug "Valtype now: ". $rec->{'valtype'} if $DEBUG;
    debug "Coltype now: $coltype" if $DEBUG;

    if( my $obj_id = $props->{'obj_id'} )
    {
	$coltype = 'obj';
	$value = $obj_id;
	$rec->{$coltype} = $value;
	push @fields, $coltype;
	push @values, $rec->{$coltype};

	$value_obj = Rit::Base::Resource->get_by_id( $obj_id );
    }
    else
    {
	# It's possible we are creating an arc with an undef value.
	# That is allowed!

	unless( defined $props->{'value'} )
	{
	    $props->{'value'} = $props->{'obj'};
	}
	$value = $props->{'value'};
	if( defined $value )
	{
	    if( UNIVERSAL::can $value, 'defined' )
	    {
		# All good
	    }
	    elsif( ref $value )
	    {
		if( ref $value eq 'HASH' )
		{
		    # Find relative the callers arclims
		    $value = Rit::Base::Resource->find_one($value, $args);
		}
		else
		{
		    throw('validation', "Malformed value given: $value");
		}
	    }
	    else
	    {
		# Find relative the callers arclims
		$value = Rit::Base::Resource->get_by_label( $value,
							    {
							     %$args,
							     coltype => $coltype,
							    });
	    }

	    check_value(\$value);
	}
	else
	{
	    $value = is_undef;
	}

	$value_obj = $value;
	debug "value_obj is now '$value_obj'" if $DEBUG;

	if( $value->defined )
	{
	    # Coltype says how the value should be stored.  The predicate
	    # specifies the coltype.  But it is possible that the value is
	    # an object even if it should be another coltype.  This will
	    # happen if the value is a value node.  In that case, the
	    # coltype will be set as obj.

	    $coltype = 'obj' if UNIVERSAL::isa( $value, 'Rit::Base::Resource' );

	    if( $coltype eq 'obj' )
	    {
		if( UNIVERSAL::isa($value, 'Rit::Base::Resource::Compatible' ) )
		{
		    # All good
		}
		else
		{
		    confess "Value incompatible with coltype $coltype: ".datadump($props, 2);
		}
	    }
	    else
	    {
		if( UNIVERSAL::isa($value, 'Rit::Base::Resource::Compatible' ) )
		{
		    confess "Value incompatible with coltype $coltype: ".datadump($props, 2);
		}
		else
		{
		    # All good
		}
	    }


	    if( $coltype eq 'obj' )
	    {
		debug "Getting the id for the object by the name '$value'\n" if $DEBUG;
		( $value ) = $this->resolve_obj_id( $value );
	    }
	    elsif( $coltype eq 'valdate' )
	    {
		$value = $dbix->format_datetime($value);
	    }
	    else
	    {
		$value = $value->literal;

		if( $coltype eq 'valtext' )
		{
		    $rec->{'valclean'} = valclean( $value );
		    die "Object stringification ".datadump($rec, 2) if $rec->{'valclean'} =~ /^ritbase.*hash/;
		    push @fields, 'valclean';
		    push @values, $rec->{'valclean'};
		}
	    }

	    $rec->{$coltype} = $value;
	    push @fields, $coltype;
	    push @values, $rec->{$coltype};

	    debug "Create arc $pred_name($rec->{'subj'}, $rec->{$coltype})\n" if $DEBUG;
	}
	else
	{
	    debug "Create arc $pred_name($rec->{'subj'}, undef)\n" if $DEBUG;
	}
    }


    # Do not create duplicate arcs.  Check if arc with subj, pred, val
    # already exists. This checks if the arc already is existing. It
    # doesn't match on other properties. ( TODO: Also consider the
    # read_access value.)


    {
	my $subj = Rit::Base::Resource->get_by_id( $rec->{'subj'} );
	my $pred = Rit::Base::Pred->get( $rec->{'pred'} );


	# Also returns new and submitted arcs, from the same user

	debug( sprintf "Check if subj %s has pred %s with value %s", $rec->{'subj'}, $pred->plain, query_desig($value_obj) ) if $DEBUG;

#	debug "Getting arclist for ".$subj->sysdesig;
	# $value_obj may be is_undef (but not literal undef)
	my $existing_arcs = $subj->arc_list($pred, $value_obj, ['active', 'submitted', 'new']);

#	debug "Existing arcs: ".query_desig($existing_arcs) if $DEBUG;
#	debug "value_obj: '$value_obj'";

      EXISTING:
	foreach my $arc ($existing_arcs->as_array)
	{
	    if( $rec->{'replaces'} )
	    {
		next unless $arc->replaces_id == $rec->{'replaces'};
	    }

	    if( $props->{'common_id'} ) # Explicitly defined
	    {
		next unless $arc->common_id == $props->{'common_id'};
	    }

	    debug "Checking at existing arc ".$arc->sysdesig if $DEBUG;

	    if( $arc->active )
	    {
		debug $arc->desig. " already exist" if $DEBUG;

		# See if there already is another suggested version of
		# this arc not equal to this version
		foreach my $rarc ($arc->versions(undef,[['new','created_by_me'],['submitted','created_by_me']])->as_array)
		{
		    next if $rarc->equals($arc);

		    if( $rarc->is_removal )
		    {
			debug "Revokes unactivated removal requests";
			$rarc->remove({force=>1});
		    }
		    else
		    {
			# There is another suggested change of this
			# arc that would collide with this
			# version. Therefore, we cannot use this
			# common arc.

			debug "The new arc would collide with ".
			  $rarc->sysdesig;
			next EXISTING;
		    }
		}

		return $arc;
	    }

	    if( $arc->created_by->equals( $Para::Frame::REQ->user ) )
	    {
		debug $arc->desig. " already exist, but not active" if $DEBUG;
		$res->add_newarc( $arc );
		return $arc;
	    }
	}
    }

    # Don't allow arcs where subj and obj is the same node:
    #
    if( $rec->{obj} and ( $rec->{'subj'} == $rec->{obj} ) )
    {
	confess "Cyclic references not allowed\n".datadump($rec,2);
	throw('validation', "Cyclic references not allowed\n");
    }


#    debug "Would have created new arc..."; return is_undef; ### DEBUG


    my $fields_part = join ",", @fields;
    my $values_part = join ",", map "?", @fields;
    my $st = "insert into arc($fields_part) values ($values_part)";
    my $sth = $dbix->dbh->prepare($st);
    warn "SQL $st (@values)\n" if $DEBUG;

    $sth->execute( @values );

    my $arc = $this->get_by_rec($rec, $subj, $value_obj );
    debug "Created arc id ".$arc->sysdesig."\n";

    # Sanity check
    if( $subj and $subj->id != $arc->subj->id )
    {
	confess "Creation of arc arc->{id} resulted in confused subj: ".datadump($subj,2).datadump($arc->subj,2);
    }
    if( $value_obj and not $value_obj->equals($arc->value) )
    {
	confess "Creation of arc arc->{id} resulted in confused value: ".datadump($value_obj,2).datadump($arc->value,2);
    }

    ######## Has not been done by get_by_rec.
    ##
    ## This may have been a new arc added to an exisiting initiated
    ## node. That means that that object must be updated to reflect
    ## the existence of the new arc. A normal init of an arc does not
    ## require the subj and obj to be resetted.
    #
    $arc->subj->initiate_cache;
    $arc->value->initiate_cache($arc);

    $arc->schedule_check_create;

    $res->changes_add;

    cache_update;

    send_cache_update({ change => 'arc_created',
			arc_id => $arc->common_id,
		      });

    $res->add_newarc( $arc );

    return $arc;
}

#######################################################################

=head2 find

  Rit::Base::Arc->find( \%props, \%args )

The props:

  subj : Anything that L<Rit::Base::Resource/get> takes

  subj_id : Same as C<subj>

  pred : Anything that L<Rit::Base::Resource/get> takes, called as
  L<Rit::Base::Pred>

  pred_id : Same as C<pred>

  obj_id : The id of the obj as a plain integer

  value : May be L<Rit::Base::Undef>, any L<Rit::Base::Literal> or a
  L<Rit::Base::Resource>

  obj : Same as L<value>

You may give one, two or three of C<subj>, C<pred> and C<value>.

Returns: A C<Rit::Base::List> of arcs.

=cut

sub find
{
    my( $this, $props, $args ) = @_;
    my $class = ref($this) || $this;

    # NB! The props values should be plain values


    my( @values, @parts );

    if( $props->{'subj'} )
    {
	$props->{subj_id} ||= $props->{'subj'}->id;
    }
    elsif( $props->{'subj_id'} )
    {
	$props->{'subj'} = Rit::Base::Arc->get( $props->{'subj_id'}, $args );
    }

    if( $props->{'subj_id'} )
    {
	push @parts, "subj=?";
	push @values, $props->{'subj_id'};
    }

    if( defined $props->{'active'} )
    {
	if( $props->{'active'} )
	{
	    push @parts, "active is true";
	}
	else
	{
	    push @parts, "active is false";
	}
    }
    else
    {
	# FIND ACTIVE VERSION
	push @parts, "active is true";
    }

    my $pred = Rit::Base::Pred->get( $props->{'pred_id'} ||
					     $props->{'pred'} );
    if( $pred )
    {
	push @parts, "pred=?";
	push @values, $pred->id;
    }

    unless( defined $props->{'value'} )
    {
	$props->{'value'} = $props->{'obj'};
    }

    if( defined $props->{'value'} )
    {
	my $value = $props->{'value'};
	$pred or die "pred_id missing";
	my $coltype = $pred->coltype;
	if( $coltype eq 'obj'  )
	{
	    ( $value ) = $this->resolve_obj_id( $value );
	}

	if( ref $value )
	{
	    $value = $value->plain;
	}

	push @parts, "$coltype=?";
	push @values, $value;
    }
    elsif( my $value = $props->{'obj_id'} )
    {
	$pred or die "pred_id missing";
	my $coltype = $pred->coltype;
	unless( $coltype eq 'obj'  )
	{
	    die "Pred '$pred->{'id'}' is not of obj type";
	}

	push @parts, "$coltype=?";
	push @values, $value;
    }

    unless( @parts )
    {
	confess "Insufficient arguments: ".datadump($props,2);
    }

    my $and_part = join " and ", @parts;
    my $st = "select * from arc where $and_part";
    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare($st);
#    warn "Executing $st\Values: @values\n";
    $sth->execute(@values);

    my @arcs;
    my $subj = $props->{'subj'};
    while( my $arc_rec = $sth->fetchrow_hashref )
    {
	# Why would I not want to disregard those?
	#
	my $arc = $class->get_by_rec( $arc_rec, $subj );
	if( $arc->disregard )
	{
	    warn "Disregarding arc ".$arc->sysdesig."\n";
	}
	else
	{
	    push @arcs, $arc;
	}
    }
    $sth->finish;

    return new Rit::Base::List( \@arcs );
}

#######################################################################

=head2 find_set

  Rit::Base::Arc->find_set( \%props, \%args )

Finds the one matching arc or create one.

Default default is C<{}>.

Calls L</find> with the given props.

If no arc are found, we go through all the default predicates. If the
predicate isn't part of C<%props>, the property s added. After that,
L</create> is called with the modified C<%props>.

If more than one arc is found, tries to eliminate one of them by
calling L</remove_duplicates>.

Supported args are:

  default
  arclim
  res

Exceptions:

  alternatives - More than one arc matches the criterions

Returns: The arc

=cut

sub find_set
{
    my( $this, $props, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $arcs = $this->find( $props, $args );

    my $default = $args->{'default'} || {};

    if( $arcs->[1] )
    {
	# Try to eliminate duplicate arcs
	$arcs->[1]->remove_duplicates( $args );
	$arcs = $this->find( $props, $args );
    }

    if( $arcs->[1] )
    {
	my $result = $Para::Frame::REQ->result;
	$result->{'info'}{'alternatives'}{'alts'} = $arcs;
	$result->{'info'}{'alternatives'}{'query'} = $props;
	$result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	throw('alternatives', "More than one arc matches the criterions");
    }
    unless( $arcs->[0] )
    {
	foreach my $pred ( keys %$default )
	{
	    $props->{$pred} ||= $default->{$pred};
	}
	return $this->create($props, $args );
    }

    my $arc = $arcs->[0];
    return $arc;
}

#######################################################################

=head2 find_remove

  Rit::Base::Arc->find_remove(\%props, \%args )

Remove matching arcs if existing.

Calls L</find> with the given props.

Calls L</remove> for each found arc.

If the property C<implicit> is given, the value of it is passed on to
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

    my $arcs = $this->find( $props, $args );

    foreach my $arc ( $arcs->nodes )
    {
	$arc->remove( $args );
    }
}

#######################################################################

=head2 find_one

  Rit::Base::Arc->fins_one( \%props, \%args )

Calls L</find> with the given props.

Supported args are:

  arclim

Exceptions:

  alternatives - More than one arc matches the criterions

  notfound - No arcs match the criterions

Returns: The arc

=cut

sub find_one
{
    my( $this, $props, $args ) = @_;

    my $arcs = $this->find( $props, $args );

    if( $arcs->[1] )
    {
	my $result = $Para::Frame::REQ->result;
	$result->{'info'}{'alternatives'}{'alts'} = $arcs;
	$result->{'info'}{'alternatives'}{'query'} = $props;
	throw('alternatives', "More than one arc matches the criterions");
    }
    unless( $arcs->[0] )
    {
	warn datadump($props,2);
	throw('notfound', "No arcs match the criterions");
    }

    return $arcs->[0];
}



#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

#######################################################################

=head2 subj

  $a->subj

Returns: The subject L<Rit::Base::Resource> of the arc

=cut

sub subj
{
    my( $arc ) = @_;
    # We use the subj for determining if the arc is removed or not
    return $arc->{'subj'} || is_undef;
}

#######################################################################

=head2 pred

  $a->pred

Returns: The L<Rit::Base::Pred> of the arc

=cut

sub pred
{
    my( $arc ) = @_;
    return $arc->{'pred'} || is_undef ;
}

#######################################################################

=head2 value

  $a->value

Returns: The L<Rit::Base::Node> value as a L<Rit::Base::Resource>,
L<Rit::Base::Literal> or L<Rit::Base::Undef> object.  NB! Used
internally.

The property C<value> has special handling in its dynamic use for
resourcess.  This means that you can only use this method as an ordinary
method call.  Not dynamicly from TT.

Rather use L</desig>, L</loc> or L</plain>.

=cut

sub value
{
    return $_[0]->{'value'};
}

#######################################################################

=head2 obj

  $a->obj

Returns: The object L<Rit::Base::Resource> of the arc.  If the value
of the arc isn't an object; returns L<Rit::Base::Undef>.

=cut

sub obj
{
    my( $arc ) = @_;

    if( UNIVERSAL::isa( $arc->{'value'}, 'Rit::Base::Resource::Compatible' ) )
    {
	return $arc->{'value'};
    }
    else
    {
	return is_undef;
    }
}

#######################################################################

=head2 value_desig

  $a->value_desig

A designation of the value, suitable for admin interface

=cut

sub value_desig
{
    my( $arc ) = @_;

    if( $arc->obj )
    {
	return sprintf("'%s'", $arc->obj->desig );
    }
    else
    {
	my $value = $arc->value || is_undef->as_string;
	return sprintf("'%s'", truncstring($value));
    }
}

#######################################################################

=head2 value_sysdesig

  $a->value_sysdesig

Returns: A plain string with a designation of the value, suitable for
admin interface

=cut

sub value_sysdesig
{
    my( $arc ) = @_;
    my $val = $arc->value;
    if( ref $val )
    {
	return $arc->value->sysdesig;
    }
    elsif( $val )
    {
	return "Strange value '$val'";
    }
    else
    {
	return "<undef>";
    }
}

#######################################################################

=head2 created

  $a->created

Returns: The time as an L<Rit::Base::Time> object, or
L<Rit::Base::Undef>.

=cut

sub created
{
    my( $arc ) = @_;
    return $arc->{'arc_created'} || is_undef;
}

#######################################################################

=head2 updated

  $a->updated

Returns: The time as an L<Rit::Base::Time> object, or
L<Rit::Base::Undef>.

=cut

sub updated
{
    my( $arc ) = @_;
    return $arc->{'arc_updated'} || is_undef;
}

#######################################################################

=head2 activated

  $a->activated

Returns: The time as an L<Rit::Base::Time> object, or
L<Rit::Base::Undef>.

=cut

sub activated
{
    my( $arc ) = @_;
    return $arc->{'arc_activated'} || is_undef;
}

#######################################################################

=head2 deactivated

  $a->deactivated

Returns: The time as an L<Rit::Base::Time> object, or
L<Rit::Base::Undef>.

=cut

sub deactivated
{
    my( $arc ) = @_;
    return $arc->{'arc_deactivated'} || is_undef;
}

#######################################################################

=head2 deactivated_by

  $a->deactivated_by

Returns: The L<Rit::Base::Resource> of the deactivator, or
L<Rit::Base::Undef>.

=cut

sub deactivated_by
{
    my( $arc ) = @_;
    my $class = ref($arc);

    if( $arc->{'arc_deactivated_by_obj'} )
    {
	debug "Returning cached deactivated_by obj";
	return $arc->{'arc_deactivated_by_obj'};
    }

    my $deactivated_by =
    my $deactivated = $arc->{'arc_deactivated'};
    unless( $deactivated )
    {
	debug "Returning undef deactivated_by obj";
	return is_undef;
    }

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? and activated = (select deactivated from arc where ver=?)");
    my $common_id = $arc->common_id;
    my $id = $arc->id;
    debug "Searching for deactivated_by with $common_id and $id";
    $sth->execute($arc->common_id, $arc->id);

    my $aarc;
    if( my $arc_rec = $sth->fetchrow_hashref )
    {
	$aarc = $class->get_by_rec( $arc_rec );
    }
    $sth->finish;

    unless( $aarc )
    {
	debug "deactivated_by obj not found";
	return is_undef;
    }

    debug "Returning deactivated_by obj from ".$aarc->sysdesig;
    return $arc->{'arc_deactivated_by_obj'} = $aarc->activated_by;
}

#######################################################################

=head2 unsubmitted

  $a->unsubmitted

NB: This is not the reverse of L</submitted>

C<unsubmitted> means that the submission has been taken back.  The
date of the submission is the L</updated> time, if the L</submitted>
flag is set.

Returns: The time as an L<Rit::Base::Time> object, or
L<Rit::Base::Undef>.

=cut

sub unsubmitted
{
    my( $arc ) = @_;
    return $arc->{'arc_unsubmitted'} || is_undef;
}

#######################################################################

=head2 updated_by

  $a->updated_by

See L</created_by>

=cut

sub updated_by
{
    return $_[0]->created_by;
}

#######################################################################

=head2 activated_by

  $a->activated_by

Returns: The L<Rit::Base::Resource> of the activator, or
L<Rit::Base::Undef>.

=cut

sub activated_by
{
    my( $arc ) = @_;
    return $arc->{'activated_by_obj'} ||=
      $Para::Frame::CFG->{'user_class'}->get( $arc->{'activated_by'} ) ||
	  is_undef;
}

#######################################################################

=head2 created_by

  $a->created_by

Returns: The L<Rit::Base::Resource> of the creator, or
L<Rit::Base::Undef>.

=cut

sub created_by
{
    my( $arc ) = @_;
    return $arc->{'arc_created_by_obj'} ||=
      $Para::Frame::CFG->{'user_class'}->get( $arc->{'arc_created_by'} ) ||
	  is_undef;
}

#######################################################################

=head2 version_id

  $a->version_id

=cut

sub version_id
{
    return $_[0]->{'id'};
}

#######################################################################

=head2 replaces_id

  $a->replaces_id

=cut

sub replaces_id
{
    return $_[0]->{'replaces'};
}

#######################################################################

=head2 replaces

  $a->replaces

=cut

sub replaces
{
    return Rit::Base::Arc->get_by_id($_[0]->{'replaces'});
}

#######################################################################

=head2 source

  $a->source

=cut

sub source
{
    my( $arc ) = @_;
    return $arc->{'source_obj'} ||=
      Rit::Base::Resource->get( $arc->{'source'} );
}

#######################################################################

=head2 read_access

  $a->read_access

=cut

sub read_access
{
    my( $arc ) = @_;
    return $arc->{'arc_read_access_obj'} ||=
      Rit::Base::Resource->get( $arc->{'arc_read_access'} );
}

#######################################################################

=head2 write_access

  $a->write_access

=cut

sub write_access
{
    my( $arc ) = @_;
    return $arc->{'arc_write_access_obj'} ||=
      Rit::Base::Resource->get( $arc->{'arc_write_access'} );
}

#######################################################################

=head2 is_owned_by

  $a->is_owned_by( $agent )

C<$agent> must be a Resource. It may be a L<Rit::Base::User>.

Returns: true if C<$agent> is regarded as an owner of the arc

TODO: Handle arcs where subj and obj has diffrent owners

TODO: Handle user that's members of a owner group

=cut

sub is_owned_by
{
    my( $arc, $agent ) = @_;

    if( UNIVERSAL::isa($agent, 'Rit::Base::User') )
    {
	return 1 if $agent->has_root_access;
    }

    if( not( $arc->activated ) and
	$arc->created_by->equals( $Para::Frame::REQ->user ) )
    {
	return 1;
    }


    if( $agent->equals( $arc->subj->owned_by ) )
    {
	return 1;
    }

    return 0;
}

#######################################################################

=head2 view_flags

  $a->view_flags

  A = active
  N = Not Active
  S = Submitted
  O = Old
  Di = direct
  In = indirect
  Ex = explicit
  Im = implicit

Returns: A plain string the the direct/explicit status.

Example: In Im

=cut

sub view_flags # To be used in admin view
{
    my( $node ) = @_;

    my $state;
    if( $node->active )
    {
	$state = 'A';
    }
    elsif( $node->old )
    {
	$state = 'O';
    }
    elsif( $node->submitted )
    {
	$state = 'S';
    }
    else
    {
	$state = 'N',
    }

    my $direct = $node->direct ? "Di" : "In";
    my $explicit = $node->explicit ? "Ex" : "Im";

    return "$state $direct $explicit";
}

#######################################################################

=head2 implicit

  $a->implicit

Returns: true if this arc is implicit

An implicit arc is always infered. It's always L</indirect>.

This is the oposite of L</explicit>.

=cut

sub implicit
{
    my( $arc ) = @_;
    return $arc->{'implicit'};
}

#######################################################################

=head2 explicit

  $a->explicit

Returns: true if this arc is explicit

An explicit arc is an exisitng arc that's not only created by
inference. It may be infered, but would exist even if it wasn't
infered.

This is the oposite of L</implicit>.

=cut

sub explicit
{
    my( $arc ) = @_;
    return not $arc->{'implicit'};
}


#######################################################################

=head2 indirect

  $a->indirect

Returns: true if this arc is indirect

An indirect arc is (or can be) infered from other arcs. It may be
L</explicit> or L</implicit>.

This is the oposite of L</direct>.

=cut

sub indirect
{
    my( $arc ) = @_;
    confess "undefined?!".datadump($arc,2) unless defined $arc->{'indirect'};

    return $arc->{'indirect'};
}


#######################################################################

=head2 direct

  $a->direct

Returns: true if this arc is direct

A direct arc has (or can) not be infered from other arcs. It's always
L</explicit>.

This is the oposite of L</indirect>.

=cut

sub direct
{
    my( $arc ) = @_;
    return not $arc->{'indirect'};
}


#######################################################################

=head2 active

  $a->active

Returns: true if this arc is active

=cut

sub active
{
    return $_[0]->{'active'};
}


#######################################################################

=head2 inactive

  $a->inactive

Returns: true if this arc is inactive

=cut

sub inactive
{
    return not $_[0]->{'active'};
}


#######################################################################

=head2 submitted

  $a->submitted

NB: This is not the reverse of L</unsubmitted>

C<unsubmitted> means that the submission has been taken back.  The
date of the submission is the L</updated> time, if the L</submitted>
flag is set.


Returns: true if this arc is submitted

=cut

sub submitted
{
    return $_[0]->{'submitted'};
}


#######################################################################

=head2 is_new

  $a->is_new

This is a nonactvie and nonsubmitted arc that hasn't been deactivated.

Returns: true if this arc is new

=cut

sub is_new
{
    return( !$_[0]->{'active'} &&
	    !$_[0]->{'submitted'} &&
	    !$_[0]->{'arc_deactivated'} );
}


#######################################################################

=head2 old

  $a->old

This is a arc that has been deactivated.

Returns: true if this arc is old

=cut

sub old
{
    return( $_[0]->{'arc_deactivated'} );
}


#######################################################################

=head2 active_version

  $a->active_version

May return undef;

Returns: The active arc, if there is one, even if it's this arc

=cut

sub active_version
{
    my( $arc ) = @_;
    my $class = ref($arc);

    if( $arc->active )
    {
	return $arc;
    }

    my $aarc;

    # Updates here on demand
    if( $aarc = $arc->{'active_version'} )
    {
	if( $aarc->active )
	{
	    return $aarc;
	}
	undef $aarc;
    }

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? and active is true");
    $sth->execute($arc->common_id);
    if( my $arc_rec = $sth->fetchrow_hashref )
    {
	$aarc = $class->get_by_rec( $arc_rec );
    }
    $sth->finish;

    # May be undef
    return $arc->{'active_version'} = $aarc;
}


#######################################################################

=head2 versions

  $a->versions( $proplim, $args )

Returns: A L<Rit::Base::list> of all versions of this arc

TODO: Make this a non-materialized list

=cut

sub versions
{
    my( $arc, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

#    debug "Getting versions of $arc->{id} with arclim ".$arclim->sysdesig;

    my $class = ref($arc);

    my @arcs;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? order by ver");
    $sth->execute($arc->common_id);
    while( my $arc_rec = $sth->fetchrow_hashref )
    {
	my $arc = $class->get_by_rec( $arc_rec );
	if( $arc->meets_arclim($args->{'arclim'}) )
	{
	    if( $proplim )
	    {
		if( $arc->meets_proplim( $proplim, $args ) )
		{
		    push @arcs, $arc;
		}
	    }
	    else
	    {
		push @arcs, $arc;
	    }
	}
    }
    $sth->finish;

    return Rit::Base::List->new(\@arcs);
}


#######################################################################

=head2 replaced_by

  $a->replaced_by

May return empty listref

Returns: A list of arcs replacing this version. Active or inactive

=cut

sub replaced_by
{
    my( $arc ) = @_;
    my $class = ref($arc);

    my @list;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? and replaces=?");
    $sth->execute($arc->common_id, $arc->id);
    while( my $arc_rec = $sth->fetchrow_hashref )
    {
	push @list, $class->get_by_rec( $arc_rec );
    }
    $sth->finish;

    return Rit::Base::List->new(\@list);
}


#######################################################################

=head2 common

  $a->common

TODO: Should be it's own class

Returns: The node representing the arc, regardless of version

=cut

sub common
{
    return $_[0]->{'common'} ||=
      Rit::Base::Resource->get_by_id($_[0]->{'common_id'});
}


#######################################################################

=head2 common_id

  $a->common_id

TODO: Should be it's own class

Returns: The node id representing the arc, regardless of version

=cut

sub common_id
{
    return $_[0]->{'common_id'};
}


#######################################################################

=head2 desig

  $a->desig

Returns: a plain string representation of the arc

=cut

sub desig
{
    my( $arc ) = @_;

    return sprintf("%s --%s--> %s", $arc->subj->desig, $arc->pred->plain, $arc->value_desig);
}


#######################################################################

=head2 sysdesig

  $a->sysdesig

Returns: a plain string representation of the arc, including the arc
L</id>

=cut

sub sysdesig
{
    my( $arc ) = @_;

    return sprintf("%d[%d]: %s --%s--> %s (%s%s) #%d", $arc->{'id'}, $arc->{'common_id'}, $arc->subj->sysdesig, $arc->pred->plain, $arc->value_sysdesig, $arc->view_flags, ($arc->{'disregard'}?' D':''), $arc->{'ioid'});
}


#######################################################################

=head2 sysdesig_nosubj

  $a->sysdesig_nosubj

Returns: a string representation of the arc, including the arc L</id>,
not using name lookup for the subject.

(Mosly used in debugging in places there a subject lookup would cause
infinite recursion.)

=cut

sub sysdesig_nosubj
{
    my( $arc ) = @_;

    return sprintf("%d: %s --%s--> %s (%d) #%d", $arc->{'id'}, $arc->subj->id, $arc->pred->plain, $arc->value_sysdesig, $arc->{'disregard'}, $arc->{'ioid'});
}


#######################################################################

=head2 syskey

  $a->syskey

Returns: a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("arc:%d", shift->{'id'});
}


#######################################################################

=head2 is_removed

  $a->is_removed

See if this arc is removed from the database. Only for arcs just
removed but not yet removed from all caches.

Returns: 1 or 0

=cut

sub is_removed
{
    return $_[0]->{subj} ? 0 : 1;
}


#######################################################################

=head2 is_removal

  $a->is_removal

Is this an arc version representing the deletion of an arc?

Returns: 1 or 0

=cut

sub is_removal
{
    return $_[0]->{'valtype'} ? 0 : 1;
}


#######################################################################

=head2 is_arc

  $a->is_arc

Returns: 1

=cut

sub is_arc
{
    1;
}


#######################################################################

=head2 objtype

  $a->objtype

Returns: true if the L</coltype> of the L</value> is C<obj>.

This will not return true if the real value is a value node, unless
the value node has a value that is a node.

In other words; We check what type of value this arc should have,
based on the L</pred>.

Compare with L</realy_objtype>. See also
L<Rit::Base::Resource/is_value_node>.

=cut

sub objtype
{
    return 1 if $_[0]->coltype eq 'obj';
    return 0;
}


#######################################################################

=head2 realy_objtype

  $a->realy_objtype

Returns: true if the actual value is a node.

It gives the same answer as L</objtype>, except then the value is a
value node.

Also returns true if the value is undef and should be of coltype obj.

Compare with L</objtype>. See also
L<Rit::Base::Resource/is_value_node>.

=cut

sub realy_objtype
{
    return 1 if UNIVERSAL::isa( $_[0]->{'value'}, 'Rit::Base::Resource::Compatible' );

    unless( defined $_[0]->{'value'} and $_[0]->{'value'}->defined )
    {
	return $_[0]->objtype;
    }

    return 0;
}


#######################################################################

=head2 coltype

  $a->coltype

Returns: the coltype the value will have unless the value is a value
node.

In other words; the coltype based on the L</pred>.

See L</real_coltype>, L<Rit::Base::Pred/coltype> and
L<Rit::Base::Resource/is_value_node>.

=cut

sub coltype
{
    # The arc value may be undefined.
    # Assume that all valtypes not in the COLTYPE hash are objs

    return $Rit::Base::COLTYPE_valtype2name{ $_[0]->{'valtype'} } || 'obj';
}


#######################################################################

=head2 real_coltype

  $a->real_coltype

Returns: the actual coltype of the value.

It's the same as the coltype, except if the value is a value node.

See L</coltype>, L<Rit::Base::Pred/coltype> and
L<Rit::Base::Resource/is_value_node>.

=cut

sub real_coltype
{
    my( $arc ) = @_;
    return 'obj' if UNIVERSAL::isa( $arc->{'value'}, 'Rit::Base::Resource::Compatible' );
    return $Rit::Base::COLTYPE_valtype2name{ $arc->{'valtype'} };
}


#######################################################################

=head2 valtype

  $a->valtype

Returns: the C<valtype> node for this arc.

=cut

sub valtype
{
    if( $_[0]->{'valtype'} )
    {
	return Rit::Base::Resource->get( $_[0]->{'valtype'} );
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

=head2 explain

  $a->explain( \%args )

Explains how this arc has been infered.

Returns: reference to a list of hashes with the keys 'a', 'b' and 'c'
pointing to the two arcs used in the inference and this resulting arc.
The key 'rule' points to the rule used for the inference.

The list will be empty if this is'nt an infered arc.

... May remove arcs makred as L</indirect> if they arn't L</explict>.

The explain hash is set up by L<Rit::Base::Rule/validate_infere>.

=cut

sub explain
{
    my( $arc, $args ) = @_;

    if( $arc->indirect )
    {
	if( $arc->validate_check( $args ) )
	{
#	    warn "Inference recorded\n";
	    # All good
	}
	else
	{
#	    warn "Couldn't be infered\n";
	    if( $arc->implicit )
	    {
		$arc->remove( $args );
	    }
	}
    }
    else
    {
#	warn "Not indirect\n";
    }

    return $arc->{'explain'};
}

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

#######################################################################

=head2 deactivate

  $a->deactivate( $arc )

Must give the new active arc as arg. This will be called by
L</activate> or by L</remove>.

Only active or submitted arcs can be deactivated.

Submitted arcs are not active but will be handled here. It will be
deactivated as is if it was active, since its been replaced by a new
arc.

=cut

sub deactivate
{
    my( $arc, $narc ) = @_;
    my $class = ref($arc);

    unless( $arc->active or $arc->submitted )
    {
	throw('validation', "Arc $arc->{id} is not active or submitted");
    }

    if( $narc->is_removal )
    {
	unless( $narc->activated )
	{
	    throw('validation', "Arc $narc->{id} was never activated");
	}

	# Can this arc be infered?
	if( $arc->validate_check )
	{
	    # Arc was explicit but is now indirect implicit
	    debug "Arc infered; set implicit";
	    $arc->set_implicit(1);
	    $arc->set_indirect(1);
	    return 0;
	}
    }
    elsif( not $narc->active )
    {
	throw('validation', "Arc $narc->{id} is not active");
    }


    my $updated = $narc->updated;
    my $dbix = $Rit::dbix;
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, deactivated=?, active='false', submitted='false' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $date_db, $arc->id );

    $arc->{'arc_updated'} = $updated;
    $arc->{'arc_deactivated'} = $updated;
    $arc->{'active'} = 0;
    $arc->{'submitted'} = 0;

    # Reset caches
    #
    $arc->obj->initiate_cache if $arc->obj;
    $arc->subj->initiate_cache;
    $arc->initiate_cache;
    $arc->remove_check();
    cache_update;
    send_cache_update({ change => 'arc_updated',
			arc_id => $arc->id,
		      });

    return;
}


#######################################################################

=head2 vacuum

  $a->vacuum( \%args )

Create or remove implicit arcs. Update implicit
status.

Returns: ---

=cut

sub vacuum
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs( $args_in );

    my $DEBUG = 0;

    debug "vacuum arc $arc->{id}" if $DEBUG;

    # Set global flag what we are in vacuum. Other methods will also
    # call vacuum
#    $Rit::Base::Arc::VACUUM = 1; # NO recursive vacuum

    return 1 if $res->{'vacuumed'}{$arc->{'id'}} ++;
    debug "vacuum ".$arc->sysdesig;

    $arc->remove_duplicates( $args );

#    warn "  Remove implicit\n";
    $arc->remove({%$args, implicit => 1}); ## Only removes if not valid
    unless( disregard $arc )
    {
	debug "  check activation";
	if( $arc->inactive and $arc->indirect )
	{
	    unless( $arc->active_version )
	    {
		$arc->activate({%$args, force => 1});
	    }
	}


	debug "  Reset clean";
	$arc->reset_clean($args);
	debug "  Create check";
	$arc->create_check( $args );
    }
}

#######################################################################

=head2 reset_clean

  $a->reset_clean

Sets L<Rit::Base::String/clean> based on L</value>, if it's a
string. Updates the DB.

Returns: ---

=cut

sub reset_clean
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    if( $arc->real_coltype eq 'valtext' )
    {
	my $cleaned = valclean( $arc->{'value'} );
	if( $arc->{'clean'} ne $cleaned )
	{
	    debug "Updating valclean";
	    my $dbh = $Rit::dbix->dbh;
	    my $sth = $dbh->prepare
	      ("update arc set valclean=? where ver=?");
	    die if $cleaned =~ /^ritbase/;
	    $sth->execute($cleaned, $arc->version_id);
	    $arc->{'clean'} = $cleaned;

	    cache_update;
	    send_cache_update({ change => 'arc_updated',
				arc_id => $arc->id,
			      });
	    $res->changes_add;
	}
    }
}

#######################################################################

=head2 remove_duplicates

  $a->remove_duplicates( \%args )

Removes any other arcs identical to this.

Returns: ---

=cut

sub remove_duplicates
{
    my( $arc, $args ) = @_;

    my $DEBUG = 0;

    unless( $arc->obj )
    {
	# Not implemented
	return;
    }

    warn "  Check for duplicates\n" if $DEBUG;

    # Now get a hold of the arc object existing in other
    # objects.
    # TODO: generalize this

    my $dbh = $Rit::dbix->dbh;

    my $subj = $arc->subj;
    foreach my $arc2 ( $subj->arc_list($arc->pred, undef, $args)->nodes )
    {
	next unless $arc->obj->equals( $arc2->obj, $args );
	next if $arc->id == $arc2->id;

	if( $arc2->explicit )
	{
	    $arc->set_explicit;
	}

	debug " =====================> Removing duplicate ".$arc2->sysdesig."\n";

	foreach my $rarc ( $arc2->replaced_by )
	{
	    if( $rarc->is_removal )
	    {
		$rarc->remove({%$args, force=>1});
	    }
	}

	$arc2->remove({%$args, force=>1});
    }
}

#######################################################################

=head2 has_value

  $a->has_value( $val, \%args )

Calls L</value_equals>

=cut

sub has_value
{
    shift->value_equals(@_);
}

#######################################################################

=head2 value_equals

  $a->value_equals( $val, \%args )

Supported args are

  match
  clean
  arclim

Default C<$match> is C<eq>. Other supported values are C<begins> and
C<like>.

Default C<$clean> is C<false>. If C<$clean> is true, strings will be
compared in clean mode. (You don't have to clean the C<$value> by
yourself.)

Default C<arclim> is C<active>.

Returns: true if the arc L</value> C<$match> C<$val>, given C<clean>
and C<arclim>

=cut

sub value_equals
{
    my( $arc, $val2, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    my $DEBUG = 0;

    my $match = $args->{'match'} || 'eq';
    my $clean = $args->{'clean'} || 0;

    unless( $arc->meets_arclim( $arclim ) )
    {
#	debug "  arc $arc->{id} doesn't meet arclim";
	return 0;
    }

#    debug "Compares arc ".$arc->sysdesig." with ".query_desig($val2);


    if( $arc->obj )
    {
	warn "  Compare object with $val2\n" if $DEBUG;
	if( $match eq 'eq' )
	{
	    return $arc->obj->equals( $val2, $args );
	}
	else
	{
	    return 0;
	}
    }
    elsif( ref $val2 eq 'Rit::Base::Resource' )
    {
	warn "  A value node is compared with a plain Literal\n" if $DEBUG;

	# It seems that the value of the arc is a literal.  val2 is a
	# node, probably a value node. They are not equal.

	return 0;
    }
    else
    {
	my $val1 = $arc->value->plain;
	warn "  See if $val1 $match($clean) $val2\n" if $DEBUG;
	unless( defined $val1 )
	{
	    warn "  val1 is not defined\n" if $DEBUG;
	    return 1 unless defined $val2;
	    return 0;
	}

	$val2 = $val2->plain if ref $val2;

	if( $clean )
	{
	    $val1 = valclean(\$val1);
	    $val2 = valclean(\$val2);
	}

	if( $match eq 'eq' )
	{
	    return $val1 eq $val2;
	}
	elsif( $match eq 'begins' )
	{
	    return 1 if $val1 =~ /^\Q$val2/;
	}
	elsif( $match eq 'like' )
	{
	    return 1 if $val1 =~ /\Q$val2/;
	}
	else
	{
	    confess "Matchtype $match not implemented";
	}
    }

    return 0;
}


#######################################################################

=head2 meets_arclim

  $a->meets_arclim( $arclim )

=cut

sub meets_arclim
{
    my( $arc, $arclim ) = @_;

    return 1 unless @$arclim;

#    debug "Filtering arc $arc->{id} on ".$arclim->sysdesig;
    foreach( @$arclim )
    {
#	debug "  Applying arclim $_";

	next unless Rit::Base::Arc::Lim::arc_meets_lim( $arc, $_ );



#	debug "    passed";
	return 1;
    }

#    debug "    failed";
    return 0;
}


#######################################################################

=head2 value_meets_proplim

  $a->value_meets_proplim( $proplim )

Always true if proplim is undef or an empty hashref

Returns: boolean

=cut

sub value_meets_proplim
{
    my( $arc, $proplim, $args_in ) = @_;

    return 1 unless $proplim;
    unless( ref $proplim and ref $proplim eq 'HASH' )
    {
	confess "proplim should be a hash";
    }

    return 1 unless keys %$proplim;
    if( $proplim->{'arclim'} )
    {
	confess "args given in proplim place";
    }

    if( my $obj = $arc->obj )
    {
	return 1 if $obj->meets_proplim($proplim, $args_in);
    }

    return 0;
}


#######################################################################

=head2 remove

  $a->remove( \%args )

Removes the arc. Will also remove arcs pointing to/from the arc itself.

An arc is removed by the activation (and deactivation) of a new
version with the value set to null and with valtype 0. That arc will
have the activation and deactivation date identical. This will keep
history about who requested the removal and who authorized it.

New (non-active) arcs can be removed directly by the authorized agent,
without the creation of a removal arc.


Supported args are:

  force
  implicit
  res


Default C<$implicit> bool is false.

A true value means that we want to remove an L</implict> arc.

A false value means that we want to remove an L</explicit> arc.

The C<$implicit> is used internally to remove arcs that's no
longer infered.

If called with a false value, it will remove the arc only if the arc
can't be infered. If the arc can be infered, the arc will be changed
from L</explicit> to L</implicit>.

Removal of a value arc will instead remove all arcs to the value
resource.


Returns: the number of arcs removed.

=cut

sub remove
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $DEBUG = 0;

    # If this arc is removed, there is nothing to remove
    return 0 if $arc->is_removed;

    my $implicit = $args->{'implicit'} || 0;
    my $create_removal = 0;
    my $force = $args->{'force'} || 0;

    if( $DEBUG )
    {
	debug sprintf("  Req rem arc id %s\n", $arc->sysdesig);

	my($package, $filename, $line) = caller;
	debug "  called from $package, line $line";
	debug "  implicit: $implicit";
	debug "  force: $force";
	debug "  active: ".$arc->active;
	debug "  validate_check";
#	debug "  res: ".datadump($res,2);

    }

    unless( $force )
    {
	# Remove arcs to value nod instead of the value arc
	if( $arc->pred->plain eq 'value' )
	{
	    # Only there is no other active version
	    if( $arc->active )
	    {
		debug "Removal of value arc removes ".
		  "arcs to value node instead";
		my $cnt = 0;
		foreach my $varc ( $arc->subj->revarc_list(undef,undef,['not_old'])->nodes )
		{
		    $cnt += $varc->remove( $args );
		}
		return $cnt;
	    }
	    elsif( not $arc->active_version )
	    {
		# Everything should go
		my $subj = $arc->subj;
		foreach my $oarc ( $subj->arc_list(undef,undef,['not_old'])->nodes )
		{
		    next if $oarc->equals( $arc ); # Handled below
		    $oarc->remove($args);
		}

		foreach my $oarc ( $subj->revarc_list(undef,undef,['not_old'])->nodes )
		{
		    $oarc->remove($args);
		}
	    }
	}


	if( $arc->is_removal and $arc->activated )
	{
	    debug "  Arc $arc->{id} is an removal arc. Let it be" if $DEBUG;
	    return 0;
	}

	if( ($arc->active or $arc->replaced_by->size ) and not $implicit  )
	{
	    # Create removals for active explicit arcs

	    # May be a submitted or new arc replaced by another
	    # arc. That other arc should have been removed before this
	    # one. But if this is asked to be removed, it must be done
	    # by a removal arc

	    debug "  Arc active or replaced but not flag implicit" if $DEBUG;
	    $create_removal = 1;
	}
	elsif( not $arc->is_owned_by( $Para::Frame::REQ->user ) )
	{
	    confess('denied', sprintf "You don't own the arc %s", $arc->sysdesig);
	}

	# Can this arc be infered?
	if( $arc->validate_check( $args ) )
	{
	    if( $implicit )
	    {
		debug "  Arc implicit and infered" if $DEBUG;
		return 0;
	    }

	    # Arc was explicit but is now indirect implicit
	    debug "  Arc infered; set implicit" if $DEBUG;
	    if( $create_removal )
	    {
		$arc->create_removal($args);
		return 1;
	    }
	    else
	    {
		$arc->set_implicit(1);
		return 0;
	    }
	}
	else
	{
	    if( $arc->implicit )
	    {
		# This arc can not be infered, so it can't be implicit any
		# more. -- This was probably caused by some arc being
		# disregarded.  (nested inference?)

		debug "  Arc implicit but not infered" if $DEBUG;
		$implicit ++; # Implicit remove mode
	    }
	}

	if( $implicit and $arc->explicit ) # remove implicit
	{
	    debug "  removed implicit but arc explicit\n" if $DEBUG;
	    return 0;
	}
	elsif( not $implicit and $arc->implicit ) # remove explicit
	{
	    debug "  Removed explicit but arc implicit\n" if $DEBUG;
	    return 0;
	}
	elsif( not $implicit and $arc->indirect ) # remove explicit
	{
	    # This arc is no longer explicitly stated, but if it's
	    # indirectly infered, it will now be implicit

	    debug "  Removed explicit for indirect arc.  Make arc implicit\n" if $DEBUG;

	    if( $create_removal )
	    {
		$arc->create_removal($args);
		return 1;
	    }
	    else
	    {
		$arc->set_implicit(1);
		return 0;
	    }
	}

	if( $create_removal )
	{
	    $arc->create_removal($args);
	    return 1;
	}
    }

    debug "  remove_check" if $DEBUG;
    $arc->remove_check( $args );

    # May have been removed during remove_check
    return 1 if $arc->is_removed;

    debug "  SUPER::remove" if $DEBUG;
    $arc->SUPER::remove();  # Removes the arc node: the arcs properties

    my $arc_id = $arc->id;
    debug "Removed arc id ".$arc->sysdesig;
    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("delete from arc where ver=?");
    $res->changes_add;


#    debug "***** Would have removed ".$arc->sysdesig; return 1; ### DEBUG

    $sth->execute($arc_id);

    debug "  init subj" if $DEBUG;
    $arc->subj->initiate_cache;
    $arc->value->initiate_cache(undef);

    if( $arc->obj )
    {
	send_cache_update({ change => 'arc_removed',
			    subj_id => $arc->subj->id,
			    obj_id => $arc->obj->id,
			  });
    }
    else
    {
	send_cache_update({ change => 'arc_removed',
			    subj_id => $arc->subj->id,
			  });
    }

    # Clear out data from arc (and arc in cache)
    #
    # We use the subj prop to determine if this arc is removed
    #
    debug "  clear arc data\n" if $DEBUG;
    foreach my $prop (qw( subj pred_name value clean coltype valtype
			  created updated created_by implicit indirect ))
    {
	$arc->{$prop} = undef;
    }
    $arc->{disregard} ++;
    debug "  Set disregard arc $arc->{id} #$arc->{ioid}\n" if $DEBUG;

    # Remove arc from cache
    #
    delete $Rit::Base::Cache::Resource{ $arc_id };

    cache_update;

    return 1; # One arc removed
}


#######################################################################

=head2 create_removal

  $a->create_removal( \%args )

Returns: The removal arc

=cut

sub create_removal
{
    my( $arc, $args ) = @_;

    return Rit::Base::Arc->create({
				   common_id => $arc->common_id,
				   replaces_id => $arc->id,
				   active => 0,
				   subj_id => $arc->{'subj'},
				   pred_id => $arc->{'pred'},
				   value => is_undef,
				   valtype => 0,
				  }, $args);
}

#######################################################################

=head2 update

  $a->update( \%props, \%args )

Proprties:


  value: Calls L</set_value>

No other uses are implemented.

Example:

 $a->update({ value => 'Hello world' });

Returns: The arc

=cut

sub update
{
    my( $arc, $props, $args ) = @_;

    foreach my $pred_name ( keys %$props )
    {
	my $val = $props->{$pred_name};
	if( $pred_name eq 'value' )
	{
	    $arc = $arc->set_value( $val, $args );
	}
	else
	{
	    die "Not implemented: $pred_name";
	}
    }
    return $arc;
}

#######################################################################


=head2 set_value

  $a->set_value( $new_value, \%args )

Sets the L</value> of the arc.

Determines if we are dealning with L<Rit::Base::Resource> or
L<Rit::Base::Literal>.

Old and/or new value could be a value node.  Fail if old value
is obj and new value isn't.  If old is value and new is obj,
just accept that.

Returns: the arc changed, or the same arc

=cut

sub set_value
{
    my( $arc, $value_new_in, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $DEBUG = 0;

    debug "Set value of arc $arc->{'id'} to '$value_new_in'\n" if $DEBUG;

    my $coltype_old = $arc->real_coltype;

    # Get the value alternatives based on the current coltype.  That
    # is; If the previous value was an object: try to find a new
    # object.  Not a Literal.
    #
    my $value_new_list = Rit::Base::Resource->find_by_label( $value_new_in,
							     {
							      %$args,
							      coltype => $coltype_old,
							     });
    $value_new_list->defined or die "wrong input '$value_new_in'";

    if( $value_new_list->[1] ) # More than one
    {
	    # TODO: Explain 'kriterierna'
	    my $result = $Para::Frame::REQ->result;
	    $result->{'info'}{'alternatives'}{'alts'} = $value_new_list;
	    $result->{'info'}{'alternatives'}{'query'} = $value_new_in;
	    throw('alternatives', "More than one node matches the criterions");
    }

    my $value_new = $value_new_list->get_first_nos;
    unless( defined $value_new ) # Avoids using list overload
    {
	$value_new = is_undef;
    }

    my $value_old = $arc->value          || is_undef; # Is object

    my $coltype_new = $coltype_old;
    if( $value_new->is_value_node )
    {
	$coltype_new = 'obj';
    }

    # TODO: Should also verify the type of the new value
    check_value(\$value_new);


    if( $DEBUG )
    {
	debug "  value_old: $value_old\n";
	debug "  value_new: $value_new\n";
	debug "  coltype  : $coltype_new\n";
    }


    unless( $value_new->equals( $value_old, $args ) )
    {
	unless( $arc->is_new )
	{
	    my $new = Rit::Base::Arc->create({
					      common_id => $arc->common_id,
					      replaces_id => $arc->id,
					      active => 0,
					      subj_id => $arc->{'subj'},
					      pred_id => $arc->{'pred'},
					      value => $value_new,
					     }, $args );
	    return $new;
	}



	debug "    Changing value\n" if $DEBUG;

	$arc->remove_check( $args );

	my $arc_id      = $arc->id;
	my $u_node      = $Para::Frame::REQ->user;
	my $now         = now();
	my $dbix        = $Rit::dbix;
	my $dbh         = $dbix->dbh;
	my $value_db;

	if( $coltype_new eq 'obj' )
	{
	    $value_db = $value_new->id;
	    $arc->obj->initiate_cache;
	}
	elsif( $coltype_new eq 'valdate' )
	{
	    $value_db = $dbix->format_datetime($value_new);
	}
	elsif( $coltype_new eq 'valfloat' )
	{
	    $value_db = $value_new;
	}
	elsif( $coltype_new eq 'valtext' )
	{
	    $value_db = $value_new;

	    my $sth = $dbh->prepare
		("update arc set valclean=? where ver=?");
	    my $clean = $value_new->clean->plain;
#	    die if $clean =~ /^ritbase/;
	    $sth->execute($clean, $arc_id);

	    $arc->{'clean'} = $clean;
	}
	else
	{
	    debug "We do not specificaly handle coltype $coltype_new\n"
	      if $DEBUG;
	    $value_db = $value_new;
	}

	my $sth = $dbh->prepare("update arc set $coltype_new=?, ".
				       "created=?, created_by=?, updated=? ".
				       "where ver=?");

	# Turn to plain value if it's an object. (Works for both Literal, Undef and others)
	$value_db = $value_db->plain if ref $value_db;
	# Assume that ->plain() always returns charstring
	utf8::upgrade( $value_db );

	if( $coltype_new eq 'valtext' ) ### DEBUG
	{
	    my $len1 = length($value_db);
	    my $len2 = bytes::length($value_db);
	    debug "Setting value to: $value_db ($len2/$len1)";
	}

	my $now_db = $dbix->format_datetime($now);
	$sth->execute($value_db, $now_db, $u_node->id, $now_db, $arc_id);

	$arc->{'value'}      = $value_new;
	$arc->{$coltype_new} = $value_new;
	$arc->{'arc_updated'}    = $now;
	$arc->{'arc_created'}    = $now;
	$arc->{'arc_created_by'} = $u_node->id;
	$arc->{'arc_created_by_obj'} = $u_node;

	debug "UPDATED Arc $arc->{id} is created by $arc->{arc_created_by}";

	$arc->subj->initiate_cache;
	$arc->initiate_cache;

	$value_old->set_arc(undef);
	$value_new->set_arc($arc);

	$arc->schedule_check_create;
	cache_update;
	send_cache_update({ change => 'arc_updated',
			    arc_id => $arc->id,
			  });

	debug "Updated arc id $arc_id: ".$arc->desig."\n";

	$res->changes_add;
	$res->add_newarc($arc);
    }
    else
    {
	debug "    Same value\n" if $DEBUG;
    }

    return $arc;
}


#######################################################################

=head2 set_pred

  $a->set_pred( $pred, \%args )

Sets the pred to what we get from L<Rit::Base::Resource/get> called
from L<Rit::Base::Pred>.

Returns: the arc changed, or the same arc

=cut

sub set_pred
{
    my( $arc, $pred, $args ) = @_;

    my $DEBUG = 0;

    my $new_pred = getpred( $pred );
    my $new_pred_id = $new_pred->id;
    my $old_pred_id = $arc->pred->id;

    if( $new_pred_id != $old_pred_id )
    {
	debug "Update arc ".$arc->sysdesig.", setting pred to ".$new_pred->plain."\n" if $DEBUG;

	my $narc = $arc->create({
				 read_access => $arc->read_access->id,
				 write_access => $arc->write_access->id,
				 subj_id => $arc->subj->id,
				 pred => $new_pred,
				 value => $arc->value,
				}, $args);

	$arc->remove( $args );

	return $narc;
    }

    return $arc;
}

#######################################################################

=head2 submit

  $a->submit( \%args )

Submits the arc

Returns: the number of changes

Exceptions: validation

=cut

sub submit
{
    my( $arc ) = @_;

    return 0 if $arc->is_removed;

    unless( $arc->inactive )
    {
	throw('validation', "Arc is already active");
    }

    if( $arc->submitted )
    {
	throw('validation', "Arc is already submitted");
    }

    if( $arc->old )
    {
	throw('validation', "Arc is old");
    }

    my $dbix = $Rit::dbix;

    my $updated = now();
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, submitted='true' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );

    $arc->{'arc_updated'} = $updated;
    $arc->{'submitted'} = 1;

    $arc->initiate_cache;
    cache_update;

    return 1;
}

#######################################################################

=head2 resubmit

  $a->resubmit( \%args )

Submits the arc

Returns: the new arc

Exceptions: validation

=cut

sub resubmit
{
    my( $arc, $args ) = @_;

    unless( $arc->old )
    {
	throw('validation', "Arc is not old");
    }

    my $new = Rit::Base::Arc->create({
				      common_id => $arc->common_id,
				      replaces_id => $arc->id,
				      active => 0,
				      submitted => 1,
				      subj_id => $arc->{'subj'},
				      pred_id => $arc->{'pred'},
				      value => $arc->{'value'},
				     }, $args );
    return $new;
}

#######################################################################

=head2 unsubmit

  $a->unsubmit

Unsubmits the arc

Returns: the number of changes

Exceptions: validation

=cut

sub unsubmit
{
    my( $arc ) = @_;

    if( $arc->unsubmitted )
    {
	throw('validation', "Arc is not submitted");
    }

    my $dbix = $Rit::dbix;

    my $updated = now();
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, submitted='false' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );

    $arc->{'arc_updated'} = $updated;
    $arc->{'submitted'} = 0;

    $arc->initiate_cache;
    cache_update;

    return 1;
}

#######################################################################

=head2 activate

  $a->activate

Activates the arc

Returns: the number of changes

Exceptions: validation

=cut

sub activate
{
    my( $arc, $args_in ) = @_;
    my( $args ) = parse_propargs( $args_in );

    return 0 if $arc->is_removed;

    unless( $args->{'force'} )
    {
	unless( $arc->inactive )
	{
	    throw('validation', "Arc is already active");
	}

	unless( $arc->submitted )
	{
	    throw('validation', "Arc is not yet submittes");
	}
    }

    my $updated = now();
    my $activated_by = $Para::Frame::REQ->user;

    my $aarc = $arc->active_version;


    my $activated_by_id = $activated_by->id;
    my $dbix = $Rit::dbix;
    my $date_db = $dbix->format_datetime($updated);


    if( $arc->{'valtype'} ) # Not a REMOVAL arc
    {
	# Replaces is already set if this version is based on another
	# It may be another version than the currently active one

	my $st = "update arc set updated=?, activated=?, activated_by=?, active='true', submitted='false' where ver=?";
	my $sth = $dbix->dbh->prepare($st);
	$sth->execute( $date_db, $date_db, $activated_by_id, $arc->id );

	$arc->{'arc_updated'} = $updated;
	$arc->{'arc_activated'} = $updated;
	$arc->{'submitted'} = 0;
	$arc->{'active'} = 1;
	$arc->{'activated_by'} = $activated_by_id;
	$arc->{'activated_by_obj'} = $activated_by;
    }
    else # This is a REMOVAL arc
    {
	my $st = "update arc set updated=?, activated=?, activated_by=?, deactivated=?, active='false', submitted='false' where ver=?";
	my $sth = $dbix->dbh->prepare($st);
	$sth->execute( $date_db, $date_db, $activated_by_id, $date_db, $arc->id );

	$arc->{'arc_updated'} = $updated;
	$arc->{'arc_deactivated'} = $updated;
	$arc->{'arc_activated'} = $updated;
	$arc->{'submitted'} = 0;
	$arc->{'active'} = 0;
	$arc->{'activated_by'} = $activated_by_id;
	$arc->{'activated_by_obj'} = $activated_by;

	# If this is a removal of a new or submitted arc, that arc
	# should be deactivated
	if( my $rarc = $arc->replaces )
	{
	    # rarc is not active. Assume we are allowed to
	    # deactivate it
	    $rarc->deactivate( $arc );
	}
    }

    # Reset caches
    #
    $arc->obj->initiate_cache if $arc->obj;
    $arc->subj->initiate_cache;
    $arc->initiate_cache;

    $arc->schedule_check_create;
    cache_update;
    send_cache_update({ change => 'arc_updated',
			arc_id => $arc->id,
		      });


    # If this is not a removal and we have another active arc, it must
    # be deactivated
    #
    if( $aarc and $arc->{'valtype'} )
    {
	$aarc->deactivate( $arc );
    }

    return 1;
}

#########################################################################

=head1 Private methods

=cut

#######################################################################

=head2 set_explicit

  $a->set_explicit

  $a->set_explicit( $bool )

Default C<$bool> is true.

Returns: True if set to explicit

See also L</set_implicit> and L</explicit>

=cut

sub set_explicit
{
    my( $arc, $val ) = @_;
    defined $val or $val = 1;
    return not $arc->set_implicit( $val ? 0 : 1 );
}

#######################################################################

=head2 set_implicit

  $a->set_implicit

  $a->set_implicit( $bool )

Default C<$bool> is true.

Returns: True if set to explicit

See also L</set_explicit> and L</implicit>

=cut

sub set_implicit
{
    my( $arc, $val ) = @_;

    my $DEBUG = 0;

    # sets to 'true' if called without arg
    defined $val or $val = 1;

    $val = $val ? 1 : 0;
    return if $val == $arc->implicit;

    my $desc_str = $val ? 'implicit' : 'explicit';
    debug "Set $desc_str for arc id $arc->{id}: ".$arc->desig."\n" if $DEBUG;

    my $dbix      = $Rit::dbix;
    my $dbh       = $dbix->dbh;
    my $arc_ver   = $arc->version_id;
    my $u_node    = $Para::Frame::REQ->user;
    my $now       = now();
    my $now_db    = $dbix->format_datetime($now);
    my $bool      = $val ? 't' : 'f';

    my $sth = $dbh->prepare("update arc set implicit=?, ".
				   "updated=? ".
				   "where ver=?");
    $sth->execute($bool, $now_db, $u_node->id, $arc_ver);

    $arc->{'arc_updated'} = $now;
    $arc->{'implicit'} = $val;

    cache_update;
    send_cache_update({ change => 'arc_updated',
			arc_id => $arc->id,
		      });

    return $val;
}

#######################################################################

=head2 set_direct

  $a->set_direct

  $a->set_direct( $bool )

Default C<$bool> is true.

Returns: True if set to direct

See also L</set_indirect> and L</direct>

=cut

sub set_direct
{
    my( $arc, $val ) = @_;
    defined $val or $val = 1;
    return not $arc->set_indirect( $val ? 0 : 1 );
}

#######################################################################

=head2 set_indirect

  $a->set_indirect

  $a->set_indirect( $bool )

Default C<$bool> is true.

Returns: True if set to indirect

See also L</set_direct> and L</indirect>

=cut

sub set_indirect
{
    my( $arc, $val ) = @_;

    my $DEBUG = 0;

    # sets to 'true' if called without arg
    defined $val or $val = 1;

    $val = $val ? 1 : 0; # normalize
    return if $val == $arc->indirect; # Return if no change

    my $desc_str = $val ? 'indirect' : 'direct';
    debug "Set $desc_str for arc id $arc->{id}: ".$arc->desig."\n" if $DEBUG;

    my $dbix      = $Rit::dbix;
    my $dbh       = $dbix->dbh;
    my $arc_ver   = $arc->version_id;
    my $u_node    = $Para::Frame::REQ->user;
    my $now       = now();
    my $now_db    = $dbix->format_datetime($now);
    my $bool      = $val ? 't' : 'f';

    my $sth = $dbh->prepare("update arc set indirect=?, ".
				   "updated=? ".
				   "where ver=?");
    $sth->execute($bool, $now_db, $arc_ver);

    $arc->{'arc_updated'} = $now;
    $arc->{'indirect'} = $val;

    if( not $val and $arc->implicit ) # direct ==> explicit
    {
	# We can change this here because validation check is done
	# before call to set_indirect

	if( $DEBUG )
	{
	    debug "  No arc can be both direct and implicit\n";
	    debug "  This arc must change or be removed now!\n";
	}
    }

    cache_update;
    send_cache_update({ change => 'arc_updated',
			arc_id => $arc->id,
		      });

    return $val;
}


#######################################################################

=head2 get_by_rec

  $n->get_by_rec( $rec, @extra )

Returns: a node

Exceptions: see L</init>.

=cut

sub get_by_rec
{
    my $this = shift;
    my $id = $_[0]->{'ver'} or
      confess "get_by_rec misses the ver param: ".datadump($_[0],2);
    return $Rit::Base::Cache::Resource{$id}
      || $this->new($id)->first_bless(@_);
}


#########################################################################

=head2 get_by_rec_and_register

  $arc->get_by_rec_and_register($rec)

The same as L<Rit::Base::Resource/get_by_rec> except that it's makes
sure to register the arc with the subj and value nodes. The L</init>
method will call L</register_with_nodes> but it will not be called if
the arc is in the cache.

Returns: the arc

Exceptions: See L</init>

=cut

sub get_by_rec_and_register
{
    my $this = shift;

    my $id = $_[0]->{'ver'} or
      croak "get_by_rec misses the id param: ".datadump($_[0],2);

    if( my $arc = $Rit::Base::Cache::Resource{$id} )
    {
#	debug "Re-Registring arc $id";
	$arc->register_with_nodes;
	return $arc;
    }
    else
    {
#	debug "Calling firstbless for $id, with stmt"; ### DEBUG
	return $this->new($id)->first_bless(@_);
    }
}

#########################################################################

=head2 init

  $a->init()

  $a->init( $rec )

  $a->init( $rec, $subj )

  $a->init( $rec, undef, $value_obj )

  $a->init( $rec, $subj, $value_obj )

The existing subj and obj can be given, if known, to speed up the
initialization process.

Returns: the arc

=cut

sub init
{
    my( $arc, $rec, $subj, $value_obj ) = @_;

# NOTE:
# $arc->{'id'}        == $rec->{'ver'}
# $arc->{'common_id'} == $rec->{'id'}


    my $id = $arc->{'id'} or die "no id"; # Yes!

#    debug "Init arc $id with value_obj $value_obj";

    if( $rec )
    {
	$rec->{'ver'} or confess "no ver: ".datadump($rec);
	unless( $id eq $rec->{'ver'} )
	{
	    confess "id mismatch: ".datadump($arc,2).datadump($rec,2);
	}
    }
    else
    {
	my $sth_id = $Rit::dbix->dbh->prepare("select * from arc where ver = ?");
	$sth_id->execute($id);
	$rec = $sth_id->fetchrow_hashref;
	$sth_id->finish;

	unless( $rec )
	{
	    confess "Arc $id not found";
	}
    }


    my $DEBUG = 0; #1 if $id == 4558203; ### DEBUG
    if( $DEBUG )
    {
	debug "Initiating arc $id";
    }
    if( $DEBUG > 1 )
    {
	warn timediff("init");
	carp datadump($rec,2);
    }

    unless( $subj )  # This will use CACHE
    {
	$subj = Rit::Base::Resource->get( $rec->{'subj'} );
    }


    croak "Not a rec: $rec" unless ref $rec eq 'HASH';

    my $pred = Rit::Base::Pred->get( $rec->{'pred'} );

    my $value = $value_obj;
    unless( $value )
    {
	### Bootstrap coltype
	my $coltype_num = $pred->{'coltype'} or confess datadump($pred,1);
	my $coltype;
	if( $coltype_num == 6 )
	{
	    if( $rec->{'valtype'} eq '0' )
	    {
		$coltype = 0;
	    }
	    else
	    {
		$coltype = $Rit::Base::COLTYPE_valtype2name{ $rec->{'valtype'} }
		  or confess "Couldn't find coltype for valtype $rec->{'valtype'}";
	    }
	}
	else
	{
	    $coltype = $Rit::Base::COLTYPE_num2name{ $coltype_num };
	}

	if( $rec->{'obj'} )
	{
	    # Set value to obj, even if coltype is a literal, since the obj
	    # could be a value node
	    $value = Rit::Base::Resource->get_by_id( $rec->{'obj'} );
	}
	elsif( $coltype eq 'valdate')
	{
	    $value = Rit::Base::Time->get( $rec->{'valdate'} );
	}
	elsif( $coltype eq '0' )
	{
	    $value = is_undef;
	}
	else
	{
	    if( $rec->{$coltype} )
	    {
#		### DECODE UTF8 from database
#		utf8::decode( $rec->{$coltype} );

		### Check for and correct accidental multiple encodings
		if( $rec->{$coltype} =~ /Ã./ )
		{
		    my $val = $rec->{$coltype};
		    if( utf8::decode( $val ) )
		    {
			debug "Corrected multiple encoding for arc $id";
			$rec->{$coltype} = $val;
		    }
		}
	    }

#	    warn "  Setting $coltype value to '$rec->{$coltype}'\n" if $DEBUG;
	    $value = Rit::Base::String->new( $rec->{$coltype} );
	}
    }

    if( defined $value )
    {
	check_value(\$value);
    }
    else
    {
	$value = is_undef;
    }


    my $clean = $rec->{'valclean'};
    my $implicit =  $rec->{'implicit'} || 0; # default
    my $indirect = $rec->{'indirect'}  || 0; # default
    my $updated = Rit::Base::Time->get($rec->{'updated'} );
    my $created = Rit::Base::Time->get($rec->{'created'} );
    my $created_by = $rec->{'created_by'};
    my $arc_activated = Rit::Base::Time->get($rec->{'activated'} );
    my $arc_deactivated = Rit::Base::Time->get($rec->{'deactivated'} );
    my $arc_unsubmitted = Rit::Base::Time->get($rec->{'unsubmitted'} );

    # Setup data
    $arc->{'id'} = $id; # This is $rec->{'ver'}
    $arc->{'subj'} = $subj;
    $arc->{'pred'} = $pred;
    $arc->{'value'} = $value;  # can be Rit::Base::Undef
    $arc->{'clean'} = $clean;
    $arc->{'implicit'} = $implicit;
    $arc->{'indirect'} = $indirect;
    $arc->{'disregard'} ||= 0; ### Keep previous value
    $arc->{'in_remove_chek'} = 0;
    $arc->{'explain'} = []; # See explain() method
    $arc->{'ioid'} ||= ++ $Rit::Base::Arc; # To track obj identity
    $arc->{'common_id'} = $rec->{'id'}; # Compare with $rec->{'ver'}
    $arc->{'replaces'} = $rec->{'replaces'};
    $arc->{'source'} = $rec->{'source'};
    $arc->{'active'} = $rec->{'active'};
    $arc->{'submitted'} = $rec->{'submitted'};
    $arc->{'activated_by'} = $rec->{'activated_by'};
    $arc->{'unsubmitted'} = $arc_unsubmitted;
    $arc->{'valtype'} = $rec->{'valtype'}; # Get obj on demand
    $arc->{'arc_created_by'} = $created_by;
    $arc->{'arc_created'} = $created;
    $arc->{'arc_updated'} = $updated;
    $arc->{'arc_read_access'} = $rec->{'read_access'};
    $arc->{'arc_write_access'} = $rec->{'write_access'};
    $arc->{'arc_activated'} = $arc_activated;
    $arc->{'arc_deactivated'} = $arc_deactivated;
    #
    ####################################


    # Store arc in cache (if not yet done)
    #
#    debug "Caching node $id: $arc";
    $Rit::Base::Cache::Resource{ $id } = $arc;


    # Register with the subj and obj
    #
    $arc->register_with_nodes;

    warn "Arc $arc->{id} $arc->{ioid} ($value) has disregard value $arc->{'disregard'}\n" if $DEBUG > 1;
    if( $DEBUG > 1 )
    {
	my $pred_name = $pred->plain;
	warn "arcs for $subj->{id} $pred_name:\n";
	foreach my $arc ( @{$subj->{'relarc'}{ $pred_name }} )
	{
	    warn "- ".$arc->id."\n";
	}

	warn "revarcs for $subj->{id} $pred_name:\n";
	foreach my $revarc ( @{$subj->{'revarc'}{ $pred_name }} )
	{
	    warn "- ".$revarc->id."\n";
	}
    }

    # The node sense of the arc should NOT be resetted. It must have
    # been initialized on object creation

    warn timediff("arc init done") if $DEBUG > 1;

    return $arc;
}


#######################################################################

=head2 register_with_nodes

  $a->register_with_nodes

Returns: the arc

=cut

sub register_with_nodes
{
    my( $arc ) = @_;

    my $id = $arc->{'id'};
    my $pred = $arc->pred;
    my $subj = $arc->{'subj'};
    my $pred_name = $pred->plain;
    my $coltype = $arc->real_coltype || ''; # coltype may be removal

#    debug "--> Registring arc $id with subj $arc->{subj}{id} and obj";

    # Register the arc hos the subj
    unless( $subj->{'arc_id'}{$id}  )
    {
	if( $arc->{'active'} )
	{
	    if( ref $subj->{'relarc'}{ $pred_name } )
	    {
		push @{$subj->{'relarc'}{ $pred_name }}, $arc;
	    }
	    else
	    {
		$subj->{'relarc'}{ $pred_name } = [$arc];
	    }
	}
	else
	{
	    if( ref $subj->{'relarc_inactive'}{ $pred_name } )
	    {
		push @{$subj->{'relarc_inactive'}{ $pred_name }}, $arc;
	    }
	    else
	    {
		$subj->{'relarc_inactive'}{ $pred_name } = [$arc];
	    }
	}

	$subj->{'arc_id'}{$id} = $arc;

#	debug "RELARC:";
#	debug datadump( $subj->{'relarc'}, 1);
    }

    # Setup Value
    my $value = $arc->{'value'};
    if( defined $value )
    {
	check_value(\$value);
    }

    # Register the arc hos the obj
    if( $coltype eq 'obj' )
    {
	if( UNIVERSAL::isa($value, "ARRAY") )
	{
	    confess "bad value ".datadump($value,2);
	}

	unless( $value->{'arc_id'}{$id} )
	{
	    if( $arc->{'active'} )
	    {
		if( ref $value->{'revarc'}{ $pred_name } )
		{
		    push @{$value->{'revarc'}{ $pred_name }}, $arc;
		}
		else
		{
		    $value->{'revarc'}{ $pred_name } = [$arc];
		}
	    }
	    else
	    {
		if( ref $value->{'revarc_inactive'}{ $pred_name } )
		{
		    push @{$value->{'revarc_inactive'}{ $pred_name }}, $arc;
		}
		else
		{
		    $value->{'revarc_inactive'}{ $pred_name } = [$arc];
		}
	    }

	    $value->{'arc_id'}{$id} = $arc;
	}
    }
    elsif( defined $value )
    {
	# Remember the arc this Literal belongs to
	$value->set_arc( $arc );
    }

    return $arc;
}


#######################################################################

=head2 disregard

  $a->disregard

Each time arcs are created or removed the inference rules are
checked. The arc may be infered from other arcs or other arcs may be
infered from this arc.

Arcs that are about to be removed (in the current "transaction") or
already have been removed but still are refered to in other places,
has a positive C<disregard> value to indicate that it should not bu
used for inferences.

We also has to differ between disregarded arcs and actually removed
arcs.

Returns: True if arc is to be disregarded

TODO: Rewrite L</vacuum> and $Rit::Base::Arc::VACUUM

=cut

sub disregard
{
    my( $arc ) = @_;
    if($arc->{'disregard'})
    {
#	debug "Disregarding arc ".$arc->sysdesig."\n";
#	debug "  value is $arc->{'disregard'}\n";
	return 1;
    }
    elsif( $Rit::Base::Arc::VACUUM )
    {
	$arc->vacuum;
    }
    return $arc->{'disregard'};
}


#######################################################################

=head2 not_disregarded

  $a->not_disregarded

Returns true if this arc should not be disregarded.

The disregard does only need to be checked in the middle of an arc
removal.

=cut

sub not_disregarded
{
    return $_[0]->{'disregard'} ? 0 : 1;
}


###############################################################

=head2 schedule_check_create

  $a->schedule_check_create

Schedueled checks of newly added/modified arcs

Returns: ---

=cut

sub schedule_check_create
{
    my( $arc ) = @_;

    if( $Rit::Base::Arc::lock_check ||= 0 )
    {
	push @Rit::Base::Arc::queue_check, $arc;
	debug "Added ".$arc->sysdesig." to queue check";
    }
    else
    {
	$arc->create_check;
    }
}


###############################################################

=head2 lock

  $a->lock

Returns: ---

=cut

sub lock
{
    my $cnt = ++ $Rit::Base::Arc::lock_check;
    my $DEBUG = 0;
    if( $DEBUG )
    {
	my($package, $filename, $line) = caller;
	warn "  Arc lock up on level $cnt, called from $package, line $line\n";
    }
}


###############################################################

=head2 unlock

  $a->unlock

Returns: ---

=cut

sub unlock
{
    my $cnt = -- $Rit::Base::Arc::lock_check;
    if( $cnt < 0 )
    {
	confess "Unlock called without previous lock";
    }

    my $DEBUG = 0;
    if( $DEBUG )
    {
	my($package, $filename, $line) = caller;
	warn "  Arc lock on level $cnt, called from $package, line $line\n";
    }

    if( $cnt == 0 )
    {
	while( my $arc = shift @Rit::Base::Arc::queue_check )
	{
	    $arc->create_check;
	}
    }
}

###############################################################

=head2 unlock_all

  $a->unlock_all

Returns: ---

=cut

sub unlock_all
{
    $Rit::Base::Arc::lock_check ||= 0;
    $Rit::Base::Arc::lock_check = 0 if $Rit::Base::Arc::lock_check < 0;

    while( $Rit::Base::Arc::lock_check )
    {
	Rit::Base::Arc->unlock;
    }
}

###############################################################

=head2 clear_queue

  $a->clear_queue

Returns: ---

=cut

sub clear_queue
{
    @Rit::Base::Arc::queue_check = ();
    $Rit::Base::Arc::lock_check = 0;
}


###############################################################

=head2 validate_check

  $a->validate_check

Check if we should infere

for validation and remove: marking the arcs as to be disregarded in
those methods. Check for $arc->disregard before considering an arc

Returns: true if this arc can be infered from other arcs

=cut

sub validate_check
{
    my( $arc ) = @_;

    my $DEBUG = 0;


    # If this arc is removed, there is nothing to validate
    return 0 if $arc->is_removed;

    $arc->{'disregard'} ++;
    warn "Set disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n" if $DEBUG;

    my $validated = 0;
    my $pred      = $arc->pred;

    warn( sprintf "$$:   Retrieve list C for pred %s in %s\n",
	  $pred->plain, $arc->sysdesig) if $DEBUG;

    $arc->{'explain'} = []; # Reset the explain list

    if( my $list_c = Rit::Base::Rule->list_c($pred) )
    {
	foreach my $rule ( @$list_c )
	{
	    $validated += $rule->validate_infere( $arc );
	}
    }
    warn( "$$:   List C done\n") if $DEBUG;

    # Mark arc if it's indirect or not
    $arc->set_indirect( $validated );

    $arc->{'disregard'} --;
    if( $DEBUG )
    {
	warn "Unset disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n";
	warn "  Validation for $arc->{id} is $validated\n";
    }
    return $validated;
}


###############################################################

=head2 create_check

  $a->create_check( \%args )

Creates new arcs infered from this arc.

May also change subject class.

Returns: ---

=cut

sub create_check
{
    my( $arc, $args ) = @_;

    my $pred      = $arc->pred;
    my $DEBUG = 0;


    if( my $list_a = Rit::Base::Rule->list_a($pred) )
    {
	foreach my $rule ( @$list_a )
	{
	    $rule->create_infere_rel($arc);
	}
    }

    if( my $list_b = Rit::Base::Rule->list_b($pred) )
    {
	foreach my $rule ( @$list_b )
	{
	    $rule->create_infere_rev($arc);
	}
    }

    # Special creation rules
    #
    my $pred_name = $arc->pred->plain;
    my $subj = $arc->subj;

    if( $pred_name eq 'is' )
    {
	$subj->rebless;
    }

    $subj->on_arc_add($arc, $pred_name, $args);
 }



###############################################################

=head2 remove_check

  $a->remove_check( \%args )

Removes implicit arcs infered from this arc

May also change subject class.

Returns: ---

=cut

sub remove_check
{
    my( $arc, $args ) = @_;

    my $DEBUG = 0;

    return if $arc->{'in_remove_check'};

    # We must do the checks even if the arc is set disregard already

    # arc removed (or changed) *after* this sub

    $arc->{'in_remove_check'} ++;
    $arc->{'disregard'} ++;
    warn "Set disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n" if $DEBUG;

    my $pred      = $arc->pred;

    if( my $list_a = Rit::Base::Rule->list_a($pred) )
    {
	foreach my $rule ( @$list_a )
	{
	    $rule->remove_infered_rel($arc);
	}
    }

    if( my $list_b = Rit::Base::Rule->list_b($pred) )
    {
	foreach my $rule ( @$list_b )
	{
	    $rule->remove_infered_rev($arc);
	}
    }


    # Special remove rules
    #
    my $pred_name = $pred->plain;
    my $subj = $arc->subj;

    if( $pred_name eq 'is' )
    {
	$subj->rebless;
    }

    $subj->on_arc_del($arc, $pred_name, $args);

    $arc->{'disregard'} --;
    $arc->{'in_remove_check'} --;
    warn "Unset disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n" if $DEBUG;
}

###################################################################

=head1 Functions

=head2 timediff

  timediff( $label )

Returns: Number of miliseconds from last call, formatted with
C<$label>

=cut

sub timediff
{
    my $ts = $Rit::Base::timestamp;
    $Rit::Base::timestamp = time;
    return sprintf "%20s: %2.3f\n", $_[0], time - $ts;
}



###############################################################

=head2 check_value

  check_value( \$val )

Checks that the value is a L<Rit::Base::Resource> or a
L<Rit::Base::Literal>.

If the value is a L<Rit::Base::List> with only one element; replaces
the value with that element.

Exceptions:

Dies with stacktrace if the value doesn't checks out.

Returns: ---

=cut

sub check_value
{
    my( $valref ) = @_;

    my $val = $$valref;
#    debug "Checking value";

    if( UNIVERSAL::isa($val, "Rit::Base::List" ) )
    {
	if( $val->size > 1 )
	{
	    confess "Multiple values in value list: ".datadump($val,2);
	}
	elsif( $val->size == 0 )
	{
	    confess "Empty value list: ".datadump($val,2);
	}
	else
	{
	    $$valref = $val->get_first_nos;
	}
    }
    elsif( UNIVERSAL::isa($val, "Rit::Base::Resource::Compatible" ) )
    {
	# all good
    }
    elsif( UNIVERSAL::isa($val, "Rit::Base::Literal" ) )
    {
	if( UNIVERSAL::isa($val, "Rit::Base::String" ) )
	{
	    my $value = $val->literal;

	    if( utf8::is_utf8($value) )
	    {
		if( utf8::valid($value) )
		{
		    if( $value =~ /Ã./ )
		    {
			debug "Value '$value' DOUBLE ENCODED!!!";
		    }
		}
		else
		{
		    confess "Value '$value' marked as INVALID utf8";
		}
	    }
	    else
	    {
		debug "Value '$value' NOT Marked as utf8; upgrading";
		utf8::upgrade( $val->{'value'} );
	    }
	}
	# all good
    }
    else
    {
	confess "Strange value: ".datadump($val,2);
    }
}

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>

=cut
