#  $Id$  -*-cperl-*-
package Rit::Base::Arc;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Arc

=cut

use utf8;

use Carp qw( cluck confess carp croak shortmess );
use strict;
use Time::HiRes qw( time );
use Scalar::Util qw( refaddr blessed );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}


use Para::Frame::Utils qw( throw debug datadump package_to_module );
use Para::Frame::Reload;
use Para::Frame::Widget qw( jump );
use Para::Frame::L10N qw( loc );
use Para::Frame::Logging;

use Rit::Base::List;
use Rit::Base::Arc::List;
use Rit::Base::Pred;
use Rit::Base::Resource::Literal;
use Rit::Base::Literal::Class;
use Rit::Base::Literal;
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now );
use Rit::Base::Rule;

use Rit::Base::Utils qw( valclean translate is_undef truncstring
                         query_desig parse_propargs
                         );

use constant CLUE_NOARC => 1;
use constant CLUE_NOUSEREVARC => 2;
use constant CLUE_VALUENODE => 4;
use constant CLUE_NOVALUENODE => 8;

### Inherit
#
use base qw( Rit::Base::Resource );

# TODO:
# Move from implicit to explicit then updating implicit properties
# explicitly

use overload 'cmp'  => sub{0};
use overload 'ne'   => sub{1};
use overload 'eq'   => sub{0}; # Use method ->equals()
use overload 'fallback' => 1;

## This will make "if($arc)" false if the arc is 'removed'
## but you should use $arc->is_true or $arc->defined instead!
#
#
#use overload 'bool' => sub
#{
#    if( ref $_[0] and $_[0]->subj )
#    {
#	return 1;
#    }
#    else
#    {
#	return 0;
#    }
#};


# Dynamic preds for ARCS
our %DYNAMIC_PRED =
  (
   subj => 'resource',
   pred => 'predicate',
#   value => 'value',
   obj  => 'resource',
   value_desig => 'text',
   created => 'date',
   updated => 'date',
   activated => 'date',
   deactivated => 'date',
   deactivated_by => 'resource', # should be agent
   unsubmitted => 'date',
   updated_by => 'resource',     # should be agent
   activated_by => 'resource',   # should be agent
   created_by => 'resource',     # should be agent
   version_id => 'int',
   replaces => 'arc',
   source => 'resource',         # should be source
   read_access => 'resource',    # should be agent
   write_access => 'resource',   # should be agent
   label => 'text',
  );


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

  pred : Anything that L<Rit::Base::Resource/get> takes, called as
  L<Rit::Base::Pred>

  implicit : Makes the arc both C<implicit> and C<indirect>

  value : May be L<Rit::Base::Undef>, any L<Rit::Base::Literal> or a
  L<Rit::Base::Resource>

  obj : MUST be the id of the object, if given. Instead of C<value>

  value_node : A L<Rit::Base::Resource>

  created : Creation time. Defaults to now.

  created_by : Creator. Defaults to request user or root

Special args:

  activate_new_arcs

  submit_new_arcs

  mark_updated

  updated

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

#    Para::Frame::Logging->this_level(3);
    my $DEBUG = Para::Frame::Logging->at_level(3);

    # Clean props from array form

    foreach my $key (qw(active submitted common id replaces source
                        read_access write_access subj pred valtype
                        implicit value obj ))
    {
	if( $props->{ $key } )
	{
	    if( UNIVERSAL::isa( $props->{ $key }, 'ARRAY') )
	    {
		$props->{ $key } = $props->{ $key }->[0];
	    }
	}
    }



    if( $args->{'activate_new_arcs'} )
    {
	unless( defined $props->{'active'} )
	{
	    $props->{'active'} = $args->{'activate_new_arcs'};
	}
    }

    if( $args->{'submit_new_arcs'} )
    {
	unless( defined $props->{'submitted'} )
	{
	    $props->{'submitted'} = $args->{'submit_new_arcs'};
	}
    }


    debug "About to create arc with props:\n".query_desig($props) if $DEBUG;
#    debug "About to create arc with props:\n".datadump($props,2) if $DEBUG;

    my( @fields, @values );

    my $rec = {};

    ##################### common == id
    if( $props->{'common'} ) # used in block EXISTING
    {
	$rec->{'id'}  = $props->{'common'};
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
    if( $props->{'replaces'} )
    {
	$rec->{'replaces'}  = $props->{'replaces'};
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
	# Method may be called before constants are set up
	$rec->{'source'}  = $this->default_source->id;
    }
    push @fields, 'source';
    push @values, $rec->{'source'};


    ##################### read_access
    if( $props->{'read_access'} )
    {
	$rec->{'read_access'}  = $props->{'read_access'};
    }
    else
    {
	# Method may be called before constants are set up
	$rec->{'read_access'}  = $this->default_read_access->id;
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
	# Method may be called before constants are set up
	$rec->{'write_access'}  = $this->default_write_access->id;
    }
    push @fields, 'write_access';
    push @values, $rec->{'write_access'};


    ##################### pred_id
    my $pred = Rit::Base::Pred->get( $props->{'pred'} );
    $pred or die "Pred missing";
    my $pred_id = $pred->id;
    my $pred_name = $pred->plain;

    $rec->{'pred'} = $pred_id;

    push @fields, 'pred';
    push @values, $rec->{'pred'};


    ##################### subj
    my $subj;
    if( my $subj_label = $props->{'subj'} )
    {
	$subj = Rit::Base::Resource->get( $subj_label );

	unless( defined $subj )
	{
	    confess "No node '$subj_label' found";
	}

	if( UNIVERSAL::isa $subj, "Rit::Base::Literal" )
	{
	    # Transform to a value resource
	    $subj = $subj->node_set;
	}
    }
    else
    {
	confess "Subj missing\n";
    }
    $rec->{'subj'} = $subj->id or confess "id missing".datadump($props, 2);
    push @fields, 'subj';
    push @values, $rec->{'subj'};


    ##################### valtype
    my $valtype;
    if( $props->{'valtype'} )
    {
	$valtype = Rit::Base::Resource->get( $props->{'valtype'} );
    }
    elsif( not defined $props->{'valtype'} )
    {
	$valtype = $pred->valtype;
    }
    # Setting up the final valtype below


    ##################### updated_by
    if( $props->{'created_by'} )
    {
	$rec->{'created_by'} = Rit::Base::Resource->
	  get($props->{'created_by'})->id;
    }
    elsif( $req and $req->user )
    {
	$rec->{'created_by'} = $req->user->id;
    }
    else
    {
	$rec->{'created_by'} =
	  Rit::Base::Resource->get_by_label('root')->id;
    }
    push @fields, 'created_by';
    push @values, $rec->{'created_by'};


    ##################### updated
    if( $props->{'created'} )
    {
	$rec->{'updated'} = Rit::Base::Literal::Time->
	  get($props->{'created'});
    }
    elsif( $args->{'updated'} )
    {
	$rec->{'updated'} = Rit::Base::Literal::Time->
	  get($args->{'updated'});
    }
    else
    {
	$rec->{'updated'} = now();
    }
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


    ##################### active
    push @fields, 'active';
    unless( defined $props->{'active'} )
    {
	$props->{'active'} = 0;
    }

    # Always handle activation of replacing arcs after the creation
    # This includes removal arcs
    #
    if( $props->{'active'} and not $props->{'replaces'} )
    {
	$rec->{'active'} = 1;
	push @values, 't';

	$rec->{'activated'} = $rec->{'updated'};
	push @fields, 'activated';
	push @values, $dbix->format_datetime($rec->{'activated'});

	$rec->{'activated_by'} = $rec->{'created_by'};
	push @fields, 'activated_by';
	push @values, $rec->{'activated_by'};
    }
    else
    {
	if( $props->{'active'} )
	{
	    # Submit now. Activate later. Since we are replacing arc

	    $props->{'submitted'} = 1;
	}

	$rec->{'active'} = 0;
	push @values, 'f';
    }


    ##################### submitted
    push @fields, 'submitted';
    if( $props->{'submitted'} )
    {
	# Checking for props instead of $rec->{active} since we may be
	# planning to activate after creation in case of
	# $props->{'replaces'}
	#
	if( $props->{'active'} and not $props->{'replaces'} )
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


    ##################### obj thingy
    my $value_obj;
    # Find out the *real* coltype
    # (This gives coltype 'obj' for valtype 0 (used for REMOVAL))
    my $coltype = $valtype ? $valtype->coltype : 'obj';

    if( $DEBUG and $valtype )
    {
	debug "Valtype now: ". $valtype->id;
    }
    debug "Coltype now: ".($coltype||'') if $DEBUG;
    unless( $coltype )
    {
	debug "No coltype found: ".datadump(\%Rit::Base::Literal::Class::COLTYPE_valtype2name);
    }


    if( my $obj_id = $props->{'obj'} )
    {
	unless( $obj_id =~ /^\d+$/ )
	{
	    confess "arc obj id must be an integer";
	}

	$coltype = 'obj';
	$rec->{$coltype} = $obj_id;
	push @fields, $coltype;
	push @values, $rec->{$coltype};

	$value_obj = Rit::Base::Resource->get_by_id( $obj_id );
    }
    elsif( not $valtype ) # Special valtype for removals
    {
	$value_obj = is_undef;
    }
    else
    {
	# It's possible we are creating an arc with an undef value.
	# That is allowed!

	debug sprintf("parsing value %s (%s)", $props->{'value'}, refaddr($props->{'value'})) if $DEBUG;

	# Returns is_undef if value undef and coltype is obj
	$value_obj = Rit::Base::Resource->
	  get_by_anything( $props->{'value'},
			   {
			    %$args,
			    valtype => $valtype,
			    subj_new => $subj,
			    pred_new => $pred,
			   });

	debug sprintf("value_obj is now %s",$value_obj->sysdesig) if $DEBUG;

	if( $value_obj->defined )
	{
	    # Coltype says how the value should be stored.  The predicate
	    # specifies the coltype.

	    # Sanity check
	    #
	    if( $coltype eq 'obj' )
	    {
		unless( UNIVERSAL::isa($value_obj, 'Rit::Base::Resource' ) )
		{
		    confess "Value incompatible with coltype $coltype: ".
		      datadump($props, 2);
		}
	    }
	    elsif( UNIVERSAL::isa($value_obj, 'Rit::Base::Resource' ) )
	    {
		confess "Value incompatible with coltype $coltype: ".
		  datadump($props, 2);
	    }


	    # Handle the coltypes in the table
	    my $value;

	    # TODO: Handle in each obj class

	    if( $coltype eq 'obj' )
	    {
		debug "Getting the id for the object by the name ".($value||'') if $DEBUG;
		$value = $this->get( $value_obj )->id;
	    }
	    else # Literal
	    {
		if( $coltype eq 'valdate' )
		{
		    $value = $dbix->format_datetime($value_obj);
		}
		else
		{
		    $value = $value_obj->literal;
		    debug 2, sprintf "Plain value is %s", (defined $value?"'$value'":'<undef>');

		    if( $coltype eq 'valtext' )
		    {
			$rec->{'valclean'} = valclean( $value );

			if( $rec->{'valclean'} =~ /^ritbase.*hash/ )
			{
			    die "Object stringification ".datadump($rec, 2);
			}

			push @fields, 'valclean';
			push @values, $rec->{'valclean'};
		    }
		}

		if( $value_obj->id ) # Literal resource (value node)
		{
		    # Don't override any explicitly given value node
		    $props->{'value_node'} ||= $value_obj->id;
		}

	    }

	    $rec->{$coltype} = $value;
	    push @fields, $coltype;
	    push @values, $rec->{$coltype};

	    debug "Create arc $pred_name($rec->{'subj'}, $rec->{$coltype})" if $DEBUG;
	}
	else
	{
	    debug "Create arc $pred_name($rec->{'subj'}, undef)" if $DEBUG;
	}
    }

    ##################### value_node
    if( my $vnode_in = $props->{'value_node'} )
    {
	if( $coltype eq 'obj' )
	{
	    debug "Create props:\n".query_desig($props);
	    debug "Create args:\n".query_desig($args);
	    confess "Valuenode can not be set for non-literals ($value_obj / $vnode_in)";
	}

	my $vnode = Rit::Base::Resource->get_by_anything($vnode_in);
	push @fields, 'obj';
	push @values, $vnode->id;
	$rec->{'obj'} = $vnode->id;
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

	debug "Existing arcs: ".query_desig($existing_arcs) if $DEBUG;
#	debug "value_obj: '$value_obj'";

      EXISTING:
	foreach my $arc ($existing_arcs->as_array)
	{
	    if( $rec->{'replaces'} )
	    {
		next unless ($arc->replaces_id||0) == $rec->{'replaces'};
	    }

	    if( $props->{'common'} ) # Explicitly defined
	    {
		next unless ($arc->common_id||0) == $rec->{'id'};
	    }

	    if( $props->{'value_node'} )
	    {
		next unless ($arc->obj_id||0) == $rec->{'obj'};
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

		if( $args->{'mark_updated'} )
		{
		    $arc->mark_updated;
		}

		return $arc;
	    }

	    if( $arc->created_by->equals( $Para::Frame::REQ->user ) )
	    {
		debug $arc->desig. " already exist, but not active" if $DEBUG;

		if( $props->{'active'} )
		{
		    unless( $arc->submitted )
		    {
			$arc->submit;
		    }
		    $arc->activate;
		}
		elsif( $props->{'submitted'} )
		{
		    unless( $arc->submitted )
		    {
			$arc->submit;
		    }
		    $res->add_newarc( $arc );
		}
		else
		{
		    $res->add_newarc( $arc );
		}

		if( $args->{'mark_updated'} )
		{
		    $arc->mark_updated;
		}

		return $arc;
	    }
	}
    }

    # Don't allow arcs where subj and obj is the same node:
    #
    if( $rec->{obj} and ( $rec->{'subj'} == $rec->{obj} )
	and not $args->{'force'}
      )
    {
	confess "Cyclic references not allowed\n".datadump($rec,2);
	throw('validation', "Cyclic references not allowed\n");
    }


    ##################### Validate and update $valtype

    if( $valtype )
    {
	if( $pred->objtype )
	{
	    # Fall back on 'resource' for Undef value_obj
	    my $val_valtype = $value_obj->this_valtype ||
	      Rit::Base::Resource->get_by_id($Rit::Base::Resource::ID);

	    if( $val_valtype->id == $Rit::Base::Resource::ID )
	    {
		# Always valid
	    }
	    elsif( $valtype->id == $Rit::Base::Resource::ID )
	    {
		# Generic, to be specified
	    }
	    elsif( not $valtype->equals( $val_valtype ) )
	    {
		if( $val_valtype->scof( $valtype ) )
		{
		    # In valid range
		}
		else
		{
		    my $subjd = $subj->sysdesig;
		    my $predd = $pred->plain;
		    my $val_valtd = $val_valtype->sysdesig;
		    my $valtd = $valtype->sysdesig;
		    my $vald = $value_obj->sysdesig;
		    confess "Valtype check failed for $subjd -${predd}-> $vald ".
		      "($valtd should have been $val_valtd)";
		}
	    }

	    debug " Old valtype: ".$valtype->sysdesig if $DEBUG;
	    $valtype = $val_valtype;
	    debug " New valtype: ".$valtype->sysdesig if $DEBUG;

	    ###### Validate pred range with value

	    my $pred_valtype = $pred->valtype;
	    if( $pred_valtype->id != $Rit::Base::Resource::ID )
	    {
		if( $value_obj->is( $pred_valtype ) )
		{
		    # In valid range
		}
		else
		{
		    my $subjd = $subj->sysdesig;
		    my $predd = $pred->plain;
		    my $val_valtd = $val_valtype->sysdesig;
		    my $pred_valtd = $pred_valtype->sysdesig;
		    my $vald = $value_obj->sysdesig;
		    #throw 'validation', "Range check failed for $subjd -${predd}-> $vald ".
		    #  "(should have been $pred_valtd)";
		}
	    }
	}
	else
	{
	    # Should be ok
	}

	$rec->{'valtype'} = $valtype->id;
    }
    else # Special valtype for REMOVAL arc
    {
	$rec->{'valtype'} = 0;
    }

    push @fields, 'valtype';
    push @values, $rec->{'valtype'};



    #####################

#    debug "Would have created new arc..."; return is_undef; ### DEBUG

    my $fields_part = join ",", @fields;
    my $values_part = join ",", map "?", @fields;
    my $st = "insert into arc($fields_part) values ($values_part)";
    my $sth = $dbix->dbh->prepare($st);
    debug "SQL $st (@values)" if $DEBUG;

    $sth->execute( @values );

    my $arc = $this->get_by_rec($rec,
				{
				 subj => $subj,
				 value => $value_obj,
				});

    # If the arc was requested to be cerated active, but wasn't
    # becasue it was replacing another arc, we will activate it now

    if( $props->{'active'} and not $arc->active )
    {
	# Arc should have been submitted instead.
	$arc->activate( $args );
    }


    # Sanity check
    if( $subj and $subj->id != $arc->subj->id )
    {
	confess "Creation of arc $arc->{id} resulted in confused subj: ".
	  datadump($subj,2).datadump($arc->subj,2);
    }
    if( $value_obj and not $value_obj->equals($arc->value) )
    {
	confess "Creation of arc $arc->{id} resulted in confused value: ".
	  datadump($value_obj,2).datadump($arc->value,2);
    }


    debug "Created arc id ".$arc->sysdesig;


    ####### Has not been done by get_by_rec.
    #
    # This may have been a new arc added to an exisiting initiated
    # node. That means that that object must be updated to reflect
    # the existence of the new arc. A normal init of an arc does not
    # require the subj and obj to be resetted.
    #
    # This should not mess up init status flags for the subj and obj
    #
    $arc->register_with_nodes;


    $arc->schedule_check_create( $args );

    $res->changes_add;

    $Rit::Base::Cache::Changes::Added{$arc->id} ++;

    $res->add_newarc( $arc );

    return $arc;
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

=head2 value_node

  $a->value_node

Returns the common literal resource representing the literal. Assumes
to only be called for literal arcs. Will always return the obj field.

=cut

sub value_node
{
#    debug "Getting value node $_[0]->{id}: ".($_[0]->{'value_node'}||'<undef>');
    return( $_[0]->{'value_node_obj'} ||= $_[0]->{'value_node'}
	    ? Rit::Base::Resource::Literal->get($_[0]->{'value_node'})
	    : is_undef );
}

#######################################################################

=head2 set_value_node

  $a->set_value_node()

  $a->set_value_node( $node )

Caller should do the authorization checks

=cut

sub set_value_node
{
    my( $arc, $node, $args_in ) = @_;

    $node ||= Rit::Base::Resource::Literal->get('new');

    my $st = "update arc set obj=? where ver=?";
    my $sth = $Rit::dbix->dbh->prepare($st);
    $sth->execute( $node->id, $arc->id );

    $arc->{'value_node'} = $node->id;
    $arc->{'value_node_obj'} = $node;

    my $class = "Rit::Base::Resource::Literal";
    unless( UNIVERSAL::isa($node, $class) )
    {
	my $class_old = ref $node;
	no strict "refs";
	foreach my $class_old_real (@{"${class_old}::ISA"})
	{
	    if( my $method = $class_old_real->can("on_unbless") )
	    {
		&{$method}($node, $class, $args_in);
	    }
	}

	bless $node, $class;
    }

    return $node->init;
}

#######################################################################

=head2 obj

  $a->obj

Returns: The object L<Rit::Base::Resource> of the arc. If the arc
points to a literal resource (value node), we will return the value
node. Thus. You can't use this to determine if the arc ponts to a
literal or not. Retruns L<Rit::Base::Undef> if nothing else.

=cut

sub obj
{
    my( $arc ) = @_;

    if( $arc->coltype eq 'obj' )
    {
	return $arc->{'value'};
    }
    elsif( $arc->{'value_node'} )
    {
	return $arc->value_node;
    }
    else
    {
	return is_undef;
    }
}

#######################################################################

=head2 obj_id

  $a->obj_id


Shortcut for $a->obj->id. Returns plain undef if no id.

=cut

sub obj_id
{
    my( $arc ) = @_;

    if( $arc->coltype eq 'obj' )
    {
	return $arc->{'value'}->id;
    }
    elsif( $arc->{'value_node'} )
    {
	return $arc->{'value_node'};
    }
    else
    {
	return undef;
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

    if( $arc->objtype )
    {
	return $arc->obj->desig;
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

Returns: The time as an L<Rit::Base::Literal::Time> object, or
L<Rit::Base::Undef>.

=cut

sub created
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_created_obj'} )
    {
	return $arc->{'arc_created_obj'};
    }

    return $arc->{'arc_created_obj'} =
      Rit::Base::Literal::Time->get( $arc->{'arc_created'} );
}

#######################################################################

=head2 updated

  $a->updated

Returns: The time as an L<Rit::Base::Literal::Time> object, or
L<Rit::Base::Undef>.

=cut

sub updated
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_updated_obj'} )
    {
	return $arc->{'arc_updated_obj'};
    }

    return $arc->{'arc_updated_obj'} =
      Rit::Base::Literal::Time->get( $arc->{'arc_updated'} );
}

#######################################################################

=head2 mark_updated

  $a->mark_updated

  $a->mark_updated( $time )

Sets the update time to given time or now.

Returns the new time as a L<Rit::Base::Literal::Time>

=cut

sub mark_updated
{
    my( $arc, $time_in ) = @_;

    $time_in ||= now();
    my $time = Rit::Base::Literal::Time->get($time_in);

    my $dbix = $Rit::dbix;
    my $date_db = $dbix->format_datetime($time);
    my $st = "update arc set updated=? where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );

    $arc->{'arc_updated'} = $date_db;
    return $arc->{'arc_updated_obj'} = $time;
}

#######################################################################

=head2 activated

  $a->activated

Returns: The time as an L<Rit::Base::Literal::Time> object, or
L<Rit::Base::Undef>.

=cut

sub activated
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_activated_obj'} )
    {
	return $arc->{'arc_activated_obj'};
    }

    return $arc->{'arc_activated_obj'} =
      Rit::Base::Literal::Time->get( $arc->{'arc_activated'} );
}

#######################################################################

=head2 deactivated

  $a->deactivated

Returns: The time as an L<Rit::Base::Literal::Time> object, or
L<Rit::Base::Undef>.

=cut

sub deactivated
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_deactivated_obj'} )
    {
	return $arc->{'arc_deactivated_obj'};
    }

    return $arc->{'arc_deactivated_obj'} =
      Rit::Base::Literal::Time->get( $arc->{'arc_deactivated'} );
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
    my $deactivated = $arc->deactivated;
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

Returns: The time as an L<Rit::Base::Literal::Time> object, or
L<Rit::Base::Undef>.

=cut

sub unsubmitted
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_unsubmitted_obj'} )
    {
	return $arc->{'arc_unsubmitted_obj'};
    }

    return $arc->{'arc_unsubmitted_obj'} =
      Rit::Base::Literal::Time->get( $arc->{'arc_unsubmitted'} );
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

See: L<Rit::Base::Resource::is_owned_by>

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


    return $arc->subj->is_owned_by($agent);
}

#######################################################################

=head2 view_flags

  $a->view_flags

  A = active
  N = New
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

=head2 previous_active_version

  $a->previous_active_version

May return undef;

Returns: The arc that was active and deactivated most recently, that
is a version of this arc. Even if it's this same arc.

=cut

sub previous_active_version
{
    my( $arc ) = @_;
    my $class = ref($arc);

    my $paarc;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? and active is false and activated is not null and deactivated is not null order by deactivated desc limit 1");
    $sth->execute($arc->common_id);
    if( my $arc_rec = $sth->fetchrow_hashref )
    {
	$paarc = $class->get_by_rec( $arc_rec );
    }
    $sth->finish;

    # May be undef
    return $paarc;
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

    return Rit::Base::Arc::List->new(\@arcs);
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

    return Rit::Base::Arc::List->new(\@list);
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

    return sprintf("%d[%d]: %s --%s(%s)--> %s (%s%s) #%d", $arc->{'id'}, $arc->{'common_id'}, $arc->subj->sysdesig, ($arc->pred?$arc->pred->plain:'<undef>'), ($arc->valtype->desig), $arc->value_sysdesig, $arc->view_flags, ($arc->{'disregard'}?' D':''), $arc->{'ioid'});
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

=cut

sub objtype
{
    return 1 if $_[0]->coltype eq 'obj';
    return 0;
}


#######################################################################

=head2 coltype

  $a->coltype

Returns: the coltype the value will have.
node.

=cut

sub coltype
{
    # The arc value may be undefined.
    # Assume that all valtypes not in the COLTYPE hash are objs

#    debug "Getting coltype for $_[0]->{id}";
    return Rit::Base::Literal::Class->coltype_by_valtype_id_or_obj( $_[0]->{'valtype'} );
}


#######################################################################

=head2 valtype

  $a->valtype

Valtype 0: Removal arcs

The valtypes are nodes. Coltypes are not, and there id's doesn't match
the valtype ids.

??? Valtypes must uniquely identify the perl module class of the value.

TODO: Handle removal arcs transparently

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

=head2 this_valtype

  $a->this_valtype

This would be the same as the C<is> property of this resource. But it
must only have ONE value. It's important for literal values.

This method will return the literal valtype for value resoruces.

See also: L<Rit::Base::Literal/this_valtype>, L</is_value_node>.

Returns: The C<arc> class resource.

=cut

sub this_valtype
{
    return Rit::Base::Resource->get_by_label('arc');
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

  $a->deactivate( $arc, $args )

Must give the new active arc as arg. This will be called by
L</activate> or by L</remove>.

Only active or submitted arcs can be deactivated.

Submitted arcs are not active but will be handled here. It will be
deactivated as is if it was active, since its been replaced by a new
arc.

=cut

sub deactivate
{
    my( $arc, $narc, $args ) = @_;
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
	if( $arc->validate_check( $args ) )
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

    $arc->{'arc_updated'} = $date_db;
    $arc->{'arc_deactivated'} = $date_db;
    $arc->{'arc_updated_obj'} = $updated;
    $arc->{'arc_deactivated_obj'} = $updated;
    $arc->{'active'} = 0;
    $arc->{'submitted'} = 0;

    # Reset caches
    #
    $arc->obj->reset_cache if $arc->obj; # Literals unaffected
    $arc->subj->reset_cache;
    $arc->schedule_check_remove( $args );
    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

    $args->{'res'}->changes_add;

    debug 1, "Deactivated id ".$arc->sysdesig;

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

    # TODO: Moce value cleaning to Literal classes

    my $DEBUG = 0;

    return 1 if $res->{'vacuumed'}{$arc->{'id'}} ++;
    debug "vacuum ".$arc->sysdesig if $DEBUG;

    $arc->remove_duplicates( $args );

    my $has_obj = $arc->obj;


    if( $has_obj )
    {
	## Only removes if not valid
	debug "  Remove implicit" if $DEBUG;
	$arc->remove({%$args, implicit => 1});
    }

    unless( disregard $arc )
    {
	debug "  check activation" if $DEBUG;
	if( $arc->inactive and $arc->indirect )
	{
	    unless( $arc->active_version )
	    {
		$arc->activate({%$args, force => 1});
	    }
	}


	unless( $arc->old )
	{
	    debug "  check valtype" if $DEBUG;
	    unless( $arc->check_valtype( $args ) )
	    {
		$arc->check_value( $args );
	    }
	}

#	debug "  Reset clean";
	$arc->reset_clean($args);

	if( $has_obj )
	{
	    debug "  Create check" if $DEBUG;
	    $arc->create_check( $args );
	}

	if( $arc->active )
	{
	    $arc->validate_range;
	}
    }
}

#######################################################################

=head2 check_valtype

  $a->check_valtype( \%args )

Compares the arc valtype with the pred valtype

=cut

sub check_valtype
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs( $args_in );

#    Para::Frame::Logging->this_level(3);

    my $old_val = $arc->value;

    # Reset valtype cache
    $old_val->this_valtype_reset;

    my $pred = $arc->pred;
    my $arc_valtype = $arc->valtype;
    my $pred_valtype = $pred->valtype;
    # Falls back on arc_valtype in case of Undef
    my $old_valtype = $old_val->this_valtype || $arc_valtype;

    if( debug > 2 )
    {
	debug "Arc   valtype is ".$arc_valtype->sysdesig;
	debug "Pred  valtype is ".$pred_valtype->sysdesig;
	debug "Value         is ".$old_val->sysdesig;
	debug "Value valtype is ".$old_valtype->sysdesig;
    }


    if( $arc_valtype->equals( $old_valtype ) )
    {
#	debug "  same valtype";
	return 0;
    }
    elsif( $arc_valtype->scof( $old_valtype ) )
    {
	if( $arc->objtype )
	{
	    debug 2, "  arc valtype more specific";
	}
	else
	{
	    # Valtype in valid range
	    return 0;
	}
    }

    my $pred_coltype = $pred->coltype;

    if( debug > 1)
    {
	debug "TRANSLATION OF VALTYPE";
	debug "  for ".$arc->sysdesig;
	debug " from ".$arc_valtype->sysdesig;
	debug "   to ".$old_valtype->sysdesig;
    }

    my $newargs =
    {
     'activate_new_arcs' => $arc->active,
     'force_set_value'   => 1,
     'force_set_value_same_version' => $arc->active,
     'valtype' => $old_valtype,
    };


    if( $arc->objtype )
    {
	my $c_resource = Rit::Base::Constants->get('resource');
	if( $old_valtype->equals( $c_resource ) )
	{
	    # Valtype in valid range
	    debug 3, "  pred takes any obj";
	    return 0;
	}

	$res->changes_add;

	# TODO: this whole part could be replaced with just the nonobj
	# part, since it will also handle objs. At least if literal
	# parse can take value nodes.


	if( $pred_coltype eq 'obj' )
	{
	    if( $old_val->is($old_valtype) )
	    {
		# Old value in range
		debug 3, "old value in range";
		$arc->set_value( $old_val, $newargs );

		$old_val->vacuum;
	    }
	    elsif( $arc_valtype->equals($c_resource) )
	    {
		debug "TRANSLATION OF VALTYPE";
		debug "  for ".$arc->sysdesig;
		debug " from ".$arc_valtype->sysdesig;
		debug "   to ".$old_valtype->sysdesig;
#		debug "Trusting new given valtype";
#		confess "or not...";
		$arc->set_value( $old_val, $newargs );
		die "CHECKME";
	    }
	    else
	    {
		debug "TRANSLATION OF VALTYPE";
		debug "  for ".$arc->sysdesig;
		debug " from ".$arc_valtype->sysdesig;
		debug "   to ".$old_valtype->sysdesig;

		$Para::Frame::REQ->session->set_debug(3);
		# Reset valtype cache
		$old_val->{'valtype'} = undef;
		debug "val valtype: ".$old_val->this_valtype->sysdesig;


		confess "FIXME";
	    }
	}
	else
	{
	    # Convert resource to a literal resource

	    debug "Changing from obj to $pred_coltype";
	    debug 2, "Pred valtype is ".$pred_valtype->sysdesig;
	    debug 2, "Pred range instance class is ".$pred_valtype->instance_class;
	    debug 2, "Old valtype instance class is ".$old_valtype->instance_class;

	    my $val = $pred_valtype->instance_class->
	      new(undef, $pred_valtype);
	    $arc->set_value( $val, $newargs );
	}
    }
    else
    {
	$res->changes_add;

	if( $pred_coltype eq 'obj' )
	{
	    confess "FIXME for arc ".$arc->id;
	}
	else
	{
	    debug 3, "Setting literal";
	    debug 2, "Pred range instance class is ".$pred_valtype->instance_class;
	    my $val = $pred_valtype->instance_class->
	      parse($old_val, {
			       arc => $arc,
			       valtype => $pred_valtype,
			      });
	    $arc->set_value( $val, $newargs );
	}
    }

    return 1;
}

#######################################################################

=head2 check_value

  $a->check_value( \%args )

=cut

sub check_value
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs( $args_in );

    # TODO: Implement this
    return 0;
}

#######################################################################

=head2 reset_clean

  $a->reset_clean

Sets L<Rit::Base::Literal::String/clean> based on L</value>, if it's a
string. Updates the DB.

Returns: ---

=cut

sub reset_clean
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    # TODO: Move to literal class

    if( ($arc->coltype||'') eq 'valtext' )
    {
	my $cleaned = valclean( $arc->{'value'} );
	if( ($arc->{'clean'}||'') ne ($cleaned||'') )
	{
#	    debug "Updating valclean";
	    my $dbh = $Rit::dbix->dbh;
	    my $sth = $dbh->prepare
	      ("update arc set valclean=? where ver=?");
#	    die if $cleaned =~ /^ritbase/;
	    $sth->execute($cleaned, $arc->version_id);
	    $arc->{'clean'} = $cleaned;

	    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

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
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $DEBUG = 0;

    unless( $arc->obj )
    {
	# Not implemented
	return;
    }

    return unless $arc->active;


    debug "Check for duplicates" if $DEBUG;

    # Now get a hold of the arc object existing in other
    # objects.
    # TODO: generalize this

    my $subj = $arc->subj;
    foreach my $arc2 ( $subj->arc_list($arc->pred, undef,
				       {
					%$args,
					arclim => ['active'],
				       })->nodes )
    {
	next unless $arc->value->equals( $arc2->value, $args );
	next if $arc->id == $arc2->id;

	if( $arc2->explicit )
	{
	    $arc->set_explicit;
	}

	debug "=====================> Removing duplicate ".$arc2->sysdesig;

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

  $a->has_value({ $pred => $value }, \%args )

If given anything other than a hashref, calls L</value_equals> and returns the result.



=cut

sub has_value
{
    my( $arc, $val_in, $args_in ) = @_;

    unless( ref $val_in and ref $val_in eq 'HASH' )
    {
	return $arc->value_equals($val_in, $args_in);
    }

    my( $args ) = parse_propargs($args_in);

    my( $pred_name, $value ) = each( %$val_in );
    my $target;

    if( $DYNAMIC_PRED{ $pred_name } )
    {
	$target = $arc->$pred_name();

#	debug "has_value TARGET is ".$target->sysdesig;
    }

    unless( $target )
    {
	return $arc->SUPER::has_value($val_in, $args);
    }

    my $valtype_name = $DYNAMIC_PRED{$pred_name};
    my $valtype = Rit::Base::Resource->get_by_label($valtype_name);
    my $args_valtype =
    {
     %$args,
     valtype => $valtype,
    };
    my $R = Rit::Base->Resource;

    if( ref $value eq 'HASH' ) # Sub query
    {
	if( $target->find($value, $args)->size )
	{
	    return $arc;
	}
	return 0;
    }

    if( ref $value eq 'ARRAY' ) # $value holds alternative values
    {
	$value = Rit::Base::List->new($value);
    }

    if( UNIVERSAL::isa( $value, 'Para::Frame::List' ) )
    {
	my( $val_in, $error ) = $value->get_first;
	while(! $error )
	{
	    my $val_parsed = $R->get_by_anything($val_in, $args_valtype);
	    if( $target->equals( $val_parsed, $args ) )
	    {
		return $arc;
	    }
	}
	continue
	{
	    ( $val_in, $error ) = $value->get_next;
	};
	return 0;
    }

#    debug "CHECKS if target is equal to ".query_desig($value);

    my $val_parsed = $R->get_by_anything($value, $args_valtype);
    if( $target->equals( $val_parsed, $args ) )
    {
	return $arc;
    }

    return 0;
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
	if( $DEBUG )
	{
	    debug "Comparing values:";
	    debug "1. ".$arc->obj->sysdesig;
	    debug "2. ".query_desig($val2);
	}

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
	debug "  A normal resource is compared with a Literal" if $DEBUG;

	# It seems that the value of the arc is a literal.  val2 is a
	# node. They are not equal.

	return 0;
    }
    else
    {
	my $val1 = $arc->value->plain;
	debug "  See if $val1 $match($clean) $val2" if $DEBUG;
	unless( defined $val1 )
	{
	    debug "  val1 is not defined" if $DEBUG;
	    return 1 unless defined $val2;
	    return 0;
	}

	if( ref $val2 )
	{
	    debug "Calling plain for value $val2";
	    if( ref $val2 eq 'HASH' )
	    {
		confess query_desig( $val2 );
	    }

	    $val2 = $val2->plain;
	}

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

  $a->value_meets_proplim( $object )

Always true if proplim is undef or an empty hashref

If proplim is an object rather than an proplim, we check that the
value is equal to the object.

Returns: boolean

=cut

sub value_meets_proplim
{
    my( $arc, $proplim, $args_in ) = @_;

    return 1 unless $proplim;

    if( ref $proplim and ref $proplim eq 'HASH' )
    {
	return 1 unless keys %$proplim;
	if( $proplim->{'arclim'} )
	{
	    confess "args given in proplim place";
	}
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
  force_recursive
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
    my $force = $args->{'force'} || $args->{'force_recursive'} || 0;
    my $arc_id = $arc->id;

    if( $DEBUG )
    {
	debug "REQ REM ARC ".$arc->sysdesig;

	my($package, $filename, $line) = caller;
	debug "  called from $package, line $line";
	debug "  implicit: $implicit";
	debug "  force: $force".($args->{'force_recursive'}?' RECURSIVE':'');
	debug "  active: ".$arc->active;
	debug "  validate_check";
#	debug "  res: ".datadump($res,2);

    }

    unless( $force )
    {
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
	    # TODO: FIXME, RG::Action::pr_update can't handle this...
	    #throw('denied', sprintf "You (%s) don't own the arc %s", $Para::Frame::REQ->user->sysdesig, $arc->sysdesig);
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

	unless( $create_removal )
	{
	    foreach my $rarc ( $arc->replaced_by->nodes )
	    {
		if( $rarc->is_removal )
		{
		    unless( $rarc->replaced_by->size )
		    {
			$rarc->remove({%$args, force => 1});
			next;
		    }
		}

		$create_removal = 1;
	    }
	}

	if( $create_removal )
	{
	    $arc->create_removal($args);
	    return 1;
	}
    }

    if( $args->{'force_recursive'} )
    {
	foreach my $repl ( $arc->replaced_by->as_array )
	{
	    debug "  removes dependant version" if $DEBUG;
	    $repl->remove( $args );
	}
    }



    debug "  remove_check" if $DEBUG;
    $arc->remove_check( $args );

    # May have been removed during remove_check
    return 1 if $arc->is_removed;

    debug "  SUPER::remove" if $DEBUG;
    $arc->SUPER::remove();  # Removes the arc node: the arcs properties


    ### Not important if doesn't exist in DB. For example, if the arc
    ### was rolled back before it was comitted. We can still use this
    ### method for removing the arc from memory!

#    debug "Removed arc id ".$arc->sysdesig;
    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("delete from arc where ver=?");
    $res->changes_add;
#    debug "***** Would have removed ".$arc->sysdesig; return 1; ### DEBUG
    $sth->execute($arc_id);


    debug "  init subj" if $DEBUG;
    $arc->subj->reset_cache;
    $arc->value->reset_cache(undef);

    $Rit::Base::Cache::Changes::Removed{$arc_id} ++;

    # Clear out data from arc (and arc in cache)
    #
    # We use the subj prop to determine if this arc is removed
    #
    # Sync with init() property setup
    debug "  clear arc data\n" if $DEBUG;
    foreach my $prop (qw(
			    subj pred value value_node clean implicit
			    indirect explain replaces source active
			    submitted activated_by valtype
			    arc_created_by arc_read_access
			    arc_write_access arc_activated
			    arc_deactivated arc_created arc_updated
			    unsubmitted arc_created_obj
			    arc_updated_obj arc_activated_obj
			    arc_deactivated_obj
			    arc_deactivated_by_obj
			    arc_unsubmitted_obj activated_by_obj
			    arc_created_by_obj source_obj
			    arc_read_access_obj
			    arc_write_access_obj value_node_obj
		       ))
    {
	delete $arc->{$prop};
    }
    $arc->{disregard} ++;
    debug "  Set disregard arc $arc->{id} #$arc->{ioid}\n" if $DEBUG;

    # Remove arc from cache
    #
    delete $Rit::Base::Cache::Resource{ $arc_id };

    return 1; # One arc removed
}


#######################################################################

=head2 create_removal

  $a->create_removal( \%args )

Returns: The removal arc

=cut

sub create_removal
{
    my( $arc, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    # Should only create removals for submitted or active arcs

    # The create() method will take care of the activation of the
    # removal if args activate_new_arcs is true.

    return Rit::Base::Arc->create({
				   common      => $arc->common_id,
				   replaces    => $arc->id,
				   subj        => $arc->{'subj'},
				   pred        => $arc->{'pred'},
				   value       => is_undef,
				   valtype     => 0,
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

Supported args are:

  force_set_value
  force_set_value_same_version
  valtype
  value_node

Returns: the arc changed, or the same arc

=cut

sub set_value
{
    my( $arc, $value_new_in, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(4);

    debug 3, sprintf "Set value of arc %s to '%s'",
      $arc->{'id'}, ($value_new_in||'<undef>');

    my $coltype_old  = $arc->coltype;
    my $value_new;
    if( $args->{'force_set_value'} )
    {
	$value_new = $value_new_in;
    }
    else
    {
	# Doesn't work for removals

	my $valtype = $args->{'valtype'} || $arc->valtype;
	unless( $valtype )
	{
	    confess "Can't set the value of a removal ($value_new_in)";
	}

	debug 4, "Given valtype is ".$valtype->sysdesig;

	# Get the value alternatives based on the current coltype.  That
	# is; If the previous value was an object: try to find a new
	# object.  Not a Literal.
	#
	my $value_new_list = Rit::Base::Resource->find_by_anything
	  ( $value_new_in,
	    {
	     %$args,
	     valtype => $valtype,
	     arc     => $arc,
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

	$value_new = $value_new_list->get_first_nos;
	unless( defined $value_new ) # Avoids using list overload
	{
	    $value_new = is_undef;
	}
    }


    # Is object. May be obj representing undef value
    my $value_old = $arc->value;

    debug 4, "got new value ".$value_new->sysdesig;
    if( $value_new_in and not $value_new )
    {
	confess "We should have got a value";
    }

    my $vnode_old   = $arc->value_node;
    my $vnode_new;
    if( exists $args->{'value_node'} )
    {
	$vnode_new = Rit::Base::Resource->
	  get_by_anything($args->{'value_node'});
    }
    else
    {
	$vnode_new = $vnode_old;
    }

    if( $vnode_new )
    {
	if( UNIVERSAL::isa($value_new,'Rit::Base::Literal') )
	{
	    $value_new->node_set($vnode_new);
	}
	else
	{
	    debug $vnode_new->sysdesig." is not a value node anymore";
	    $vnode_new = is_undef;
	}
    }


    # Falling back on old coltype/valtype in case of an Undef value
    my $coltype_new = $value_new->this_coltype || $coltype_old;
    my $valtype_old = $arc->valtype;
    my $valtype_new = $value_new->this_valtype || $valtype_old;
    my $objtype_old = ($coltype_old eq 'obj')? 1 : 0;
    my $objtype_new = ($coltype_new eq 'obj')? 1 : 0;


    if( debug > 1 )
    {
	debug "  value_old: ".$value_old->sysdesig();
	debug "   type old: ".$valtype_old->sysdesig;
	debug "  vnode old: ".$vnode_old->sysdesig;
	debug "coltype old: ".$coltype_old;
	debug "  value_new: ".$value_new->sysdesig();
	debug " forced val: ".($args->{'force_set_value'}?'Yes':'No');
	debug "   type new: ".$valtype_new->sysdesig;
	debug "  vnode new: ".$vnode_new->sysdesig;
	debug "coltype new: ".$coltype_new;
    }

    my $same_value = $value_new->equals( $value_old, $args );


    unless( $same_value and
	    $valtype_new->equals( $valtype_old ) and
	    $vnode_old->equals($vnode_new)
	  )
    {
	unless( $arc->is_new or $args->{'force_set_value_same_version'} )
	{
	    my $new = Rit::Base::Arc->create({
					      common      => $arc->common_id,
					      replaces    => $arc->id,
					      subj        => $arc->{'subj'},
					      pred        => $arc->{'pred'},
					      value       => $value_new,
					      value_node  => $vnode_new,
					     }, $args );
	    return $new;
	}

	debug 3, "    Changing value\n";

	# If the value is the same, or we are changing to a literal
	# resource, we should keep infered arcs

	unless( $same_value or ($objtype_old and !$objtype_new) )
	{
	    $arc->schedule_check_remove( $args );
	}

	my $arc_id      = $arc->id;
	my $u_node      = $Para::Frame::REQ->user;
	my $now         = now();
	my $dbix        = $Rit::dbix;
	my $dbh         = $dbix->dbh;
	my $value_db;

	my @dbvalues;
	my @dbparts;

	if( $objtype_old )
	{
	    $arc->obj->reset_cache;
	}

	if( $objtype_new )
	{
	    $value_db = $value_new->id;
	    # $arc->subj->reset_cache # IS CALLED BELOW
	}
	else
	{
	    if( $coltype_new eq 'valdate' )
	    {
		$value_db = $dbix->format_datetime($value_new);
	    }
	    elsif( $coltype_new eq 'valfloat' )
	    {
		$value_db = $value_new;
	    }
	    elsif( $coltype_new eq 'valtext' )
	    {
		unless( UNIVERSAL::isa $value_new, "Rit::Base::Literal::String")
		{
		    confess "type mismatch for ".datadump($value_new,2);
		}

		$value_db = $value_new;
		my $clean = $value_new->clean_plain;

		push @dbparts, "valclean=?";
		push @dbvalues, $clean;

		$arc->{'clean'} = $clean;
	    }
	    else
	    {
		debug 3, "We do not specificaly handle coltype $coltype_new\n";
		$value_db = $value_new;
	    }
	}

	# Turn to plain value if it's an object. (Works for both Literal, Undef and others)
	$value_db = $value_db->plain if ref $value_db;
	# Assume that ->plain() always returns charstring
	utf8::upgrade( $value_db ) if defined $value_db; # May be undef

	my $now_db = $dbix->format_datetime($now);

	push( @dbparts,
	      "$coltype_new=?",
	      "valtype=?",
	      "created=?",
	      "created_by=?",
	      "updated=?"
	    );

	push( @dbvalues,
	      $value_db,
	      $valtype_new->id,
	      $now_db,
	      $u_node->id,
	      $now_db,
	    );

	if(     $objtype_old and  $objtype_new )
	{
	    # All good
	}
	elsif(  $objtype_old and !$objtype_new )
	{
	    if( $vnode_new )
	    {
		push @dbparts, "obj=?";
		push @dbvalues, $vnode_new->id; # Also works for Undef
	    }
	}
	elsif( !$objtype_old and  $objtype_new )
	{
	    push @dbparts, "$coltype_old=null";
	    $arc->{$coltype_old} = undef;
	}
	else # !$objtype_old and !$objtype_new
	{
	    if( $vnode_old or $vnode_new )
	    {
		push @dbparts, "obj=?";
		push @dbvalues, $vnode_new->id; # Also works for Undef
	    }

	    if( $coltype_old ne $coltype_new )
	    {
		push @dbparts, "$coltype_old=null";
		$arc->{$coltype_old} = undef;
	    }
	}


	my $sql_set = join ",",@dbparts;
	my $st = "update arc set $sql_set where ver=?";
	my $sth = $dbh->prepare($st);
	$sth->execute(@dbvalues, $arc_id);

	$arc->{'value'}              = $value_new;
	$arc->{$coltype_new}         = $value_new;
	$arc->{'arc_updated'}        = $now_db;
	$arc->{'arc_created'}        = $now_db;
	$arc->{'arc_updated_obj'}    = $now;
	$arc->{'arc_created_obj'}    = $now;
	$arc->{'arc_created_by'}     = $u_node->id;
	$arc->{'arc_created_by_obj'} = $u_node;
	$arc->{'valtype'}            = $valtype_new->id;
	$arc->{'value_node'}         = $vnode_new->id;
	$arc->{'value_node_obj'}     = $vnode_new;

	debug 2, "UPDATED Arc $arc->{id} is created by $arc->{arc_created_by}";

	$arc->subj->reset_cache;
#	$arc->reset_cache; # not needed
	# $arc->obj->reset_cache # IS CALLED ABOVE

	$value_old->set_arc(undef);
	$value_new->set_arc($arc);

	$arc->schedule_check_create( $args );
	$Rit::Base::Cache::Changes::Updated{$arc->id} ++;
	if( $value_old->is_resource )
	{
	    $Rit::Base::Cache::Changes::Updated{$value_old->id} ++;
	}
	if( $value_new->is_resource )
	{
	    $Rit::Base::Cache::Changes::Updated{$value_new->id} ++;
	}

	debug 0, "Updated arc ".$arc->sysdesig;

	$res->changes_add;
	$res->add_newarc($arc);
    }
    else
    {
	debug 3, "    Same value\n";
    }

    return $arc;
}


#######################################################################

=head2 set_pred

  $a->set_pred( $pred, \%args )

Sets the pred to what we get from L<Rit::Base::Resource/get> called
from L<Rit::Base::Pred>.

The old are will be removed with a removal and a new arc will be
created, not as a new version. A new version of an arc can only have a
diffrent value, not a diffrent subj or pred.

Returns: the arc changed, or the same arc

=cut

sub set_pred
{
    my( $arc, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $DEBUG = 0;

    my $new_pred = Rit::Base::Pred->get( $pred );
    my $new_pred_id = $new_pred->id;
    my $old_pred_id = $arc->pred->id;
    my $now = now();

    $args->{'updated'} = $now;

    if( $new_pred_id != $old_pred_id )
    {
	debug "Update arc ".$arc->sysdesig.", setting pred to ".$new_pred->plain."\n" if $DEBUG;

	my $narc = Rit::Base::Arc->
	  create({
		  read_access  => $arc->read_access->id,
		  write_access => $arc->write_access->id,
		  subj         => $arc->subj->id,
		  pred         => $new_pred,
		  value        => $arc->value,
		  value_node   => $arc->value_node,
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

    my $aid = $arc->id;

    unless( $arc->inactive )
    {
	throw('validation', "Arc $aid is already active");
    }

    if( $arc->submitted )
    {
	throw('validation', "Arc $aid is already submitted");
    }

    if( $arc->old )
    {
	throw('validation', "Arc $aid is old");
    }

    my $dbix = $Rit::dbix;

    my $updated = now();
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, submitted='true' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );

    $arc->{'arc_updated_obj'} = $updated;
    $arc->{'arc_updated'} = $date_db;
    $arc->{'submitted'} = 1;

#    $arc->reset_cache; # not needed

    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

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
				      common      => $arc->common_id,
				      replaces    => $arc->id,
				      active      => 0,
				      submitted   => 1,
				      subj        => $arc->{'subj'},
				      pred        => $arc->{'pred'},
				      value       => $arc->{'value'},
				      value_node  => $arc->value_node,
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

    $arc->{'arc_updated_obj'} = $updated;
    $arc->{'arc_updated'} = $date_db;
    $arc->{'submitted'} = 0;

#    $arc->reset_cache; # not needed

    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

    return 1;
}

#######################################################################

=head2 activate

  $a->activate( \%args )

Activates the arc.

Supported args:

  updated - time of activation
  force


Returns: the number of changes

Exceptions: validation

=cut

sub activate
{
    my( $arc, $args_in ) = @_;
    my( $args ) = parse_propargs( $args_in );

    return 0 if $arc->is_removed;

    my $aid = $arc->id;

    unless( $args->{'force'} )
    {
	unless( $arc->inactive )
	{
	    throw('validation', "Arc $aid is already active");
	}

	unless( $arc->submitted )
	{
	    throw('validation', "Arc $aid is not yet submitted");
	}
    }

    my $updated = $args->{'updated'} || now();
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
	$sth->execute( $date_db, $date_db, $activated_by_id, $aid );

	$arc->{'arc_updated_obj'} = $updated;
	$arc->{'arc_activated_obj'} = $updated;
	$arc->{'arc_updated'} = $date_db;
	$arc->{'arc_activated'} = $date_db;
	$arc->{'submitted'} = 0;
	$arc->{'active'} = 1;
	$arc->{'activated_by'} = $activated_by_id;
	$arc->{'activated_by_obj'} = $activated_by;
    }
    else # This is a REMOVAL arc
    {
	if( my $rarc = $arc->replaces )
	{
	    if( $rarc->old )
	    {
		debug "Target arc already removed";
		$arc->remove($args);
		return 0;
	    }
	}

	my $st = "update arc set updated=?, activated=?, activated_by=?, deactivated=?, active='false', submitted='false' where ver=?";
	my $sth = $dbix->dbh->prepare($st);
	$sth->execute( $date_db, $date_db, $activated_by_id, $date_db, $aid );

	$arc->{'arc_updated_obj'} = $updated;
	$arc->{'arc_deactivated_obj'} = $updated;
	$arc->{'arc_activated_obj'} = $updated;
	$arc->{'arc_updated'} = $date_db;
	$arc->{'arc_deactivated'} = $date_db;
	$arc->{'arc_activated'} = $date_db;
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
	    $rarc->deactivate( $arc, $args );
	}
    }

    # Reset caches
    #
    $arc->obj->reset_cache if $arc->obj;
    $arc->subj->reset_cache;
#    $arc->reset_cache;  ### Not needed. And reads from DB...

    # If this is not a removal and we have another active arc, it must
    # be deactivated
    #
    if( $aarc and $arc->{'valtype'} )
    {
	$aarc->deactivate( $arc, $args );
    }

    # Runs create_check AFTER deactivation of other arc version, since
    # the new arc version may INFERE the old arc
    #
    $arc->schedule_check_create( $args );

    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

    return 1;
}

#######################################################################

=head2 set_replaces

  $a->set_replaces( $arc2, \%args )

=cut

sub set_replaces
{
    my( $arc, $arc2, $args_in ) = @_;
    my( $args ) = parse_propargs( $args_in );

    my $common_id_old = $arc->common_id;
    my $common_id     = $arc2->common_id;

    if( $Rit::Base::Cache::Resource{ $common_id } )
    {
	confess "Too late for changing arcs common_id";
    }

    if( $arc->active )
    {
	confess "Can't set replaces for active arc";
    }

    my $arc2_id = $arc2->id;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare("update arc set id=?, replaces=? where ver=?");
    $sth->execute($common_id, $arc2_id, $arc->id);

    $arc->{'common_id'} = $common_id;
    delete $arc->{'common'};
    $arc->{'replaces'} = $arc2_id;

    return $arc;
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
    $sth->execute($bool, $now_db, $arc_ver);

    $arc->{'arc_updated_obj'} = $now;
    $arc->{'arc_updated'} = $now_db;
    $arc->{'implicit'} = $val;

    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

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

    $arc->{'arc_updated_obj'} = $now;
    $arc->{'arc_updated'} = $now_db;
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

    $Rit::Base::Cache::Changes::Updated{$arc->id} ++;

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
    my $class = ref $this || $this;
    my $id = $_[0]->{'ver'} or
      confess "get_by_rec misses the ver param: ".datadump($_[0],2);
    return $Rit::Base::Cache::Resource{$id}
      || $class->new($id, @_)->first_bless()->init(@_);
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

	# Calls init in case the arc init got an error the last time
	# and hasn't got fully initialized. The init method will do a
	# simple check and just return arc if it looks like it's
	# initialized.

	$arc->init(@_)->register_with_nodes;
	return $arc;
    }
    else
    {
#	debug "Calling firstbless for $id, with stmt"; ### DEBUG
	return $this->new($id, @_)->first_bless()->init(@_);
    }
}


#########################################################################

=head2 init

  $a->init()

  $a->init( $rec )

  $a->init( $rec, \%args )

  $a->init( undef, \%args )

The existing subj and obj can be given, if known, to speed up the
initialization process.

Supported args are:

  subj
  value
  reset

Returns: the arc

=cut

sub init
{
    my( $arc, $rec, $args ) = @_;

    my $subj = $args->{'subj'};
    my $value = $args->{'value'};
    my $reset = $args->{'reset'};

    if( $arc->{'ioid'} and not $reset )
    {
	# Arc aspect of node already initiated
	return $arc;
    }

#    my $ts = Time::HiRes::time();

    my $id = $arc->{'id'} or die "no id"; # Yes!
    my $bless_subj = 0; # For initiating subj

    $rec ||= delete $arc->{'original_rec'}; # TEST

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

#	$Para::Frame::REQ->{RBSTAT}{'arc init exec'}
#	  += Time::HiRes::time() - $ts;
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
	# Take care of recursive definition loop

	# A $n->revlist('is') will try to get the is-arcs (in
	# find_class()) in the middle of setting up the is-arcs from
	# the revlist.
	#
	# That's why we are doing the first_bless thing AFTER this arc
	# is initiated!

	unless( $subj = $Rit::Base::Cache::Resource{ $rec->{'subj'} } )
	{
	    $subj = Rit::Base::Resource->new( $rec->{'subj'} );
	    $bless_subj = 1;
	}

#	$Para::Frame::REQ->{RBSTAT}{'arc init subj'}
#	  += Time::HiRes::time() - $ts;
    }


    croak "Not a rec: $rec" unless ref $rec eq 'HASH';

    my $pred = Rit::Base::Pred->get( $rec->{'pred'} );

    my $valtype_id = $rec->{'valtype'};
    unless( $value )
    {
	### Bootstrap coltype

	if( $valtype_id == 0 ) # Removal arc
	{
	    $value = is_undef;
	}
	else
	{
	    my $valtype = Rit::Base::Resource->get($valtype_id)
	      or confess "Couldn't find the valtype $valtype_id ".
		"for arc $id";
#	    debug "Arc $id valtype is $valtype_id";

	    $value = $valtype->instance_class->get_by_arc_rec($rec,$valtype);
	}

#	$Para::Frame::REQ->{RBSTAT}{'arc init novalue'}
#	  += Time::HiRes::time() - $ts;
    }

    # Clean out old values if this is a reset
    if( $arc->{'ioid'} )
    {
	foreach my $key (qw(
			       arc_created_obj arc_updated_obj
			       arc_activated_obj arc_deactivated_obj
			       arc_deactivated_by_obj
			       arc_unsubmitted_obj activated_by_obj
			       arc_created_by_obj source_obj
			       arc_read_access_obj
			       arc_write_access_obj value_node_obj
			  ))
	{
	    delete $arc->{$key};
	}
    }

    # Sync with remove() property cleanup

    # Setup data
    $arc->{'subj'} = $subj;
    $arc->{'pred'} = $pred;
    $arc->{'value'} = $value;  # can be Rit::Base::Undef
    $arc->{'value_node'} = $pred->objtype ? undef : $rec->{'obj'};
#    debug "Setting value node of arc $id to ".($rec->{obj}||'<undef>');
    $arc->{'clean'} = $rec->{'valclean'}; # TODO: remove
    $arc->{'implicit'} = $rec->{'implicit'} || 0; # default
    $arc->{'indirect'} = $rec->{'indirect'}  || 0; # default
    $arc->{'disregard'} ||= 0; ### Keep previous value
    $arc->{'in_remove_check'} = 0;
    $arc->{'explain'} = []; # See explain() method
    $arc->{'ioid'} ||= ++ $Rit::Base::ioid; # To track obj identity
    $arc->{'common_id'} = $rec->{'id'}; # Compare with $rec->{'ver'}
    $arc->{'replaces'} = $rec->{'replaces'};
    $arc->{'source'} = $rec->{'source'};
    $arc->{'active'} = $rec->{'active'};
    $arc->{'submitted'} = $rec->{'submitted'};
    $arc->{'activated_by'} = $rec->{'activated_by'};
    $arc->{'valtype'} = $rec->{'valtype'}; # Get obj on demand
    $arc->{'arc_created_by'} = $rec->{'created_by'};
    $arc->{'arc_read_access'} = $rec->{'read_access'};
    $arc->{'arc_write_access'} = $rec->{'write_access'};
    $arc->{'arc_activated'} = $rec->{'activated'};               #
    $arc->{'arc_deactivated'} = $rec->{'deactivated'};           #
    $arc->{'arc_created'} = $rec->{'created'};                   #
    $arc->{'arc_updated'} = $rec->{'updated'};                   #
    $arc->{'unsubmitted'} = $rec->{'unsubmitted'};               #
    #
    ####################################


    # Store arc in cache (if not yet done) (Should not be needed!)
    #
    $Rit::Base::Cache::Resource{ $id } = $arc;


    # Register with the subj and obj
    #
    $arc->register_with_nodes;

    if( $DEBUG > 1 )
    {
	warn "Arc $arc->{id} $arc->{ioid} ($value) ".
	  "has disregard value $arc->{'disregard'}\n";

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

    if( $bless_subj )
    {
	debug 2, "Calling first_bless for $subj->{id}";
	$subj->first_bless->init;
    }

    # The node sense of the arc should NOT be resetted. It must have
    # been initialized on object creation

    warn timediff("arc init done") if $DEBUG > 1;

#    $Para::Frame::REQ->{RBSTAT}{'arc init'}
#      += Time::HiRes::time() - $ts;

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
    my $coltype = $arc->coltype || ''; # coltype may be removal

#    debug "--> Registring arc $id pred $pred_name with subj $arc->{subj}{id} and obj";

    # Register the arc with the subj
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

#    if( defined $value )
#    {
#	check_value(\$value); # Already initiated
#    }

    if( UNIVERSAL::isa($value, "ARRAY") )
    {
	confess "bad value ".datadump($value,2);
    }

    if( UNIVERSAL::isa($value, "Rit::Base::Literal") )
    {
	$value->set_arc($arc);
    }
    elsif( UNIVERSAL::isa($value, "Rit::Base::Resource::Literal") )
    {
	# Always revarc initiated
    }
    elsif( not $value->{'arc_id'}{$id} )
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

    # Nodes not new anymore... Not empty
    delete $subj->{'new'};
    delete $value->{'new'};

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

TODO: Rewrite L</vacuum>

=cut

sub disregard
{
    return $_[0]->{'disregard'};
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

  $a->schedule_check_create( \%args )

Schedueled checks of newly added/modified arcs

Returns: ---

=cut

sub schedule_check_create
{
    my( $arc, $args_in ) = @_;

    # Res and arclim should not be part of the args
    #
    my %args = %$args_in;
#    delete $args{'res'}; # But it IS a resulting arc
    delete $args{'arclim'};

    if( $Rit::Base::Arc::lock_check ||= 0 )
    {
	push @Rit::Base::Arc::queue_check_add, [$arc, \%args];
	debug 3, "Added ".$arc->sysdesig." to queue check add";
    }
    else
    {
	$arc->create_check( \%args );
    }
}


###############################################################

=head2 schedule_check_remove

  $a->schedule_check_remove( \%args )

Schedueled checks of newly removed arcs

Returns: ---

=cut

sub schedule_check_remove
{
    my( $arc, $args_in ) = @_;

    # Res and arclim should not be part of the args
    #
    my %args = %$args_in;
    delete $args{'res'};
    delete $args{'arclim'};

    if( $Rit::Base::Arc::lock_check ||= 0 )
    {
	push @Rit::Base::Arc::queue_check_remove, [$arc, \%args];
	debug 3, "Added ".$arc->sysdesig." to queue check remove";
    }
    else
    {
	$arc->remove_check( \%args );
    }
}


#########################################################################

=head2 rollback

=cut

sub rollback
{
#    debug "ROLLBACK LOCKED ARCS";

    while( my $params = shift @Rit::Base::Arc::queue_check_remove )
    {
	my( $arc, $args ) = @$params;
	$arc->reset_cache;
	$arc->remove_check( $args );
    }

    while( my $params = shift @Rit::Base::Arc::queue_check_add )
    {
	# These may have been rolled back. Check if they exist at all
	my( $arc, $args ) = @$params;
	my $arc_id = $arc->{'id'} or next;

	my $sth_id = $Rit::dbix->dbh->
	  prepare("select * from arc where ver = ?");
	$sth_id->execute($arc_id);
	my $rec = $sth_id->fetchrow_hashref;
	$sth_id->finish;

	if( $rec )
	{
	    $arc->reset_cache( $rec, $args );
	    $arc->create_check( $args );
	}
	else # Not added to DB
	{
	    $arc->remove({%$args,force=>1});
	}
    }

    $Rit::Base::Arc::lock_check = 0;
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
	my($package, $filename, $line) = caller(1);
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
	debug "Unlock called without previous lock";
    }

    my $DEBUG = 0;
    if( $DEBUG )
    {
	my($package, $filename, $line) = caller(1);
	warn "  Arc lock on level $cnt, called from $package, line $line\n";
    }

    if( $cnt == 0 )
    {
	while( my $params = shift @Rit::Base::Arc::queue_check_remove )
	{
	    my( $arc, $args ) = @$params;
	    $arc->remove_check( $args );
	}
	while( my $params = shift @Rit::Base::Arc::queue_check_add )
	{
	    my( $arc, $args ) = @$params;
	    $arc->create_check( $args );
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

  $a->validate_check( \%args )

Check if we should infere

for validation and remove: marking the arcs as to be disregarded in
those methods. Check for $arc->disregard before considering an arc

Returns: true if this arc can be infered from other arcs

=cut

sub validate_check
{
    my( $arc, $args ) = @_;

    my $DEBUG = 0;


    # If this arc is removed, there is nothing to validate
    return 0 if $arc->is_removed;

    $arc->{'disregard'} ++;
    debug "Set disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})" if $DEBUG;

    my $validated = 0;
    my $pred      = $arc->pred;

    debug( sprintf "  Retrieve list C for pred %s in %s",
	  $pred->plain, $arc->sysdesig) if $DEBUG;

    $arc->{'explain'} = []; # Reset the explain list

    if( my $list_c = Rit::Base::Rule->list_c($pred) )
    {
	foreach my $rule ( @$list_c )
	{
	    $validated += $rule->validate_infere( $arc, $args );
	}
    }
    debug "  List C done" if $DEBUG;

    # Mark arc if it's indirect or not
    $arc->set_indirect( $validated );

    $arc->{'disregard'} --;
    if( $DEBUG )
    {
	debug "Unset disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})";
	debug "  Validation for $arc->{id} is $validated";
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

    my $DEBUG = 0;

    return 0 unless $arc->active;

    my $pred      = $arc->pred;

    debug( sprintf  "create_check of %s",
	   $arc->sysdesig ) if $DEBUG;

    if( my $list_a = Rit::Base::Rule->list_a($pred) )
    {
	foreach my $rule ( @$list_a )
	{
	    debug( sprintf  "  using %s",
		   $rule->sysdesig) if $DEBUG;

	    $rule->create_infere_rel($arc, $args);
	}
    }

    if( my $list_b = Rit::Base::Rule->list_b($pred) )
    {
	foreach my $rule ( @$list_b )
	{
	    debug( sprintf  "  using %s",
		   $rule->sysdesig) if $DEBUG;

	    $rule->create_infere_rev($arc, $args);
	}
    }

    # Special creation rules
    #
    my $pred_name = $arc->pred->plain;
    my $subj = $arc->subj;

    if( $pred_name eq 'is' )
    {
	$subj->update_valtype($args);
	$subj->rebless( $args );
    }
    elsif( $pred_name eq 'class_handled_by_perl_module' )
    {
	# TODO: Place this in Rit::Base::Class
	$subj->on_class_perl_module_change($arc, $pred_name, $args);
    }

    $subj->on_arc_add($arc, $pred_name, $args);
 }


###############################################################

=head2 remove_check

  $a->remove_check( \%args )

Removes implicit arcs infered from this arc

Should only be called JUST BEFORE the arc is removed.

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

    # Don't make arc disregarded, because it's used in inference?
    $arc->{'disregard'} ++;
    warn "Set disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n" if $DEBUG;

    my $pred      = $arc->pred;

    # Special remove rules
    #
    my $pred_name = $pred->plain;
    my $subj = $arc->subj;

    if( $pred_name eq 'is' )
    {
	$subj->update_valtype($args);
	$subj->rebless($args);
    }
    elsif( $pred_name eq 'class_handled_by_perl_module' )
    {
	# TODO: Place this in Rit::Base::Class
	$subj->on_class_perl_module_change($arc, $pred_name, $args);
    }

    if( my $list_a = Rit::Base::Rule->list_a($pred) )
    {
	foreach my $rule ( @$list_a )
	{
	    $rule->remove_infered_rel($arc, $args);
	}
    }

    if( my $list_b = Rit::Base::Rule->list_b($pred) )
    {
	foreach my $rule ( @$list_b )
	{
	    $rule->remove_infered_rev($arc, $args);
	}
    }


    $subj->on_arc_del($arc, $pred_name, $args);

    $arc->{'in_remove_check'} --;
    $arc->{'disregard'} --;
    warn "Unset disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n" if $DEBUG;
}


###############################################################

=head2 validate_range

  $a->validate_range( \%args )

=cut

sub validate_range
{
    my( $arc, $args ) = @_;

    my $subj = $arc->subj;
    my $valtype = $arc->valtype;
    my $pred = $arc->pred;
    my $value_obj = $arc->value;

    unless( $valtype )
    {
	return 1;
    }

    unless( $pred->objtype )
    {
	return 1;
    }



    # Falling back on arc valtype in case of Undef
    my $val_valtype = $value_obj->this_valtype || $arc->valtype;

    if( $val_valtype->id == $Rit::Base::Resource::ID )
    {
	# Always valid
    }
    elsif( $valtype->id == $Rit::Base::Resource::ID )
    {
	# Generic, to be specified
    }
    elsif( not $valtype->equals( $val_valtype ) )
    {
	if( $val_valtype->scof( $valtype ) )
	{
	    # In valid range
	}
	else
	{
	    my $subjd = $subj->sysdesig;
	    my $predd = $pred->plain;
	    my $val_valtd = $val_valtype->sysdesig;
	    my $valtd = $valtype->sysdesig;
	    my $vald = $value_obj->sysdesig;
	    confess "Valtype check failed for $subjd -${predd}($valtd)-> $vald ".
	      "(should have been $val_valtd)";
	}
    }

    $valtype = $val_valtype;

    ###### Validate pred range with value

    my $pred_valtype = $pred->valtype;
    if( $pred_valtype->id != $Rit::Base::Resource::ID )
    {
	if( $value_obj->is( $pred_valtype ) )
	{
	    # In valid range
	}
	else
	{
	    my $subjd = $subj->sysdesig;
	    my $predd = $pred->plain;
	    my $val_valtd = $val_valtype->sysdesig;
	    my $pred_valtd = $pred_valtype->sysdesig;
	    my $vald = $value_obj->sysdesig;
	    #confess "Range check failed for $subjd -${predd}-> $vald ".
	    #  "(should have been $pred_valtd)";
	}
    }

    return 1;
}


###############################################################
###############################################################

=head2 edit_link_html

  $a->edit_link_html( \%args )

Displays link for updating arc

=cut

sub edit_link_html
{
    my( $arc, $args ) = @_;

    return ''
      unless $Para::Frame::REQ->user->has_root_access;

    my $home = $Para::Frame::REQ->site->home_url_path;
    my $arc_id = $arc->id;

    return
      (
       "<a href=\"$home/rb/node/arc/update.tt?".
       "id=$arc_id\" class=\"edit_arc_link\" ".
       "onmouseover=\"TagToTip('updated$arc_id')\">E</a>".
       "<span id=\"updated$arc_id\" style=\"display: none\">".
       $arc->info_updated_html($args) .
       "</span>"
      );
}


###############################################################

=head2 info_updated_html

  $a->info_updated_html( \%args )

Displays who and when arc was updated

=cut

sub info_updated_html
{
    my( $arc, $args ) = @_;

    my $home = $Para::Frame::REQ->site->home_url_path;
    my $arc_id = $arc->id;

    my $out = "";

    $out .= "<span class=\"small_note\">" . $arc->view_flags;

    if( $arc->updated_by )
    {
	$out .= " ".loc("by")." ";
	my $updated_by = $arc->updated_by;
	$out .= jump($updated_by->desig, $updated_by->form_url);
    }

    if( $arc->updated )
    {
	$out .= " " . $arc->updated;
    }

    $out .= "</span>";

    return $out;
}


###############################################################
###############################################################

=head2 default_source

=cut

sub default_source
{
    # May be called before constants init
    my $source = $Para::Frame::CFG->{'rb_default_source'};
    if( ref $source )
    {
	return $source;
    }
    else
    {
	return Rit::Base::Resource->get_by_label('ritbase');
    }
}


###############################################################

=head2 default_read_access

=cut

sub default_read_access
{
    # May be called before constants init
    my $read_access = $Para::Frame::CFG->{'rb_default_read_access'};
    if( ref $read_access )
    {
	return $read_access;
    }
    else
    {
	return Rit::Base::Resource->get_by_label('public');
    }
}


###############################################################

=head2 default_write_access

=cut

sub default_write_access
{
    # May be called before constants init
    my $write_access = $Para::Frame::CFG->{'rb_default_write_access'};
    if( ref $write_access )
    {
	return $write_access;
    }
    else
    {
	return Rit::Base::Resource->get_by_label('sysadmin_group');
    }
}


###############################################################

=head2 use_class

=cut

sub use_class
{
    return "Rit::Base::Arc";
}


###############################################################

=head2 list_class

=cut

sub list_class
{
    return "Rit::Base::Arc::List";
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


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>

=cut
