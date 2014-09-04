package RDF::Base::Arc;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Arc

=cut

use 5.014;
#no warnings "experimental";
no if $] >= 5.018, warnings => "experimental";
use utf8;
use base qw( RDF::Base::Resource );

use constant CLUE_NOARC => 1;
use constant CLUE_NOUSEREVARC => 2;
use constant CLUE_VALUENODE => 4;
use constant CLUE_NOVALUENODE => 8;

use overload 'cmp'  => sub{0};
use overload 'ne'   => sub{1};
use overload 'eq'   => sub{0}; # Use method ->equals()
use overload 'fallback' => 1;

use Carp qw( cluck confess carp croak shortmess longmess );
use Time::HiRes qw( time );
use Scalar::Util qw( refaddr blessed looks_like_number );
use DBD::Pg qw(:pg_types);
use JSON; # to_json

use Para::Frame::Utils qw( throw debug datadump package_to_module );
use Para::Frame::Reload;
use Para::Frame::Widget qw( jump );
use Para::Frame::L10N qw( loc );
use Para::Frame::Logging;

use RDF::Base::Widget;
use RDF::Base::List;
use RDF::Base::Arc::List;
use RDF::Base::Pred;
use RDF::Base::Resource::Literal;
use RDF::Base::Literal::Class;
use RDF::Base::Literal;
use RDF::Base::Literal::String;
use RDF::Base::Literal::Time qw( now );
use RDF::Base::Rule;

use RDF::Base::Utils qw( valclean is_undef truncstring
                         query_desig parse_propargs aais
                         );

# TODO:
# Move from implicit to explicit then updating implicit properties
# explicitly


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

Inherits from L<RDF::Base::Resource>.

=cut

# NOTE:
# $arc->{'id'}        == $rec->{'ver'}
# $arc->{'common_id'} == $rec->{'id'}

#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any pred object.

=cut

##############################################################################

=head2 create

  RDF::Base::Arc->create( \%props, \%args )

Creates a new arc and stores in in the DB.

The props:

  id : If undefined, gets a new id from the C<node_deq>

  subj : Anything that L<RDF::Base::Resource/get> takes

  pred : Anything that L<RDF::Base::Resource/get> takes, called as
  L<RDF::Base::Pred>

  implicit : Makes the arc both C<implicit> and C<indirect>

  value : May be L<RDF::Base::Undef>, any L<RDF::Base::Literal> or a
  L<RDF::Base::Resource>

  obj : MUST be the id of the object, if given. Instead of C<value>

  value_node : A L<RDF::Base::Resource>

  created : Creation time. Defaults to now.

  created_by : Creator. Defaults to request user or root

  updated : Defaults to creation time or now.

  active : Defaults to activate_new_arcs

  submitted : Defaults to submit_new_arcs

  common : Defaults to next new node id

  replaces : Defaults to undef

  source : Defaults to L</default_source>

  read_access : Defaults to L</default_read_access>

  write_access : Defaults to L</default_write_access>

  valtype : Defaults to L<RDF::Base::Literal/this_valtype>
            or L<RDF::Base::Pred/valtype>

  arc_weight : Defaults to C<undef>

  arc_weight_last : upon activation,
               changing the other properties as needed

Special args:

  activate_new_arcs: Sets prop active

  submit_new_arcs: Sets prop submitted

  mark_updated

  updated

  ignore_card_check: Create arc even if it violates cardinality


If value is a plain string, it's converted to an object based on L<RDF::Base::Pred/coltype>.

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
    my $dbix = $RDF::dbix;

#    Para::Frame::Logging->this_level(4);
    my $DEBUG = Para::Frame::Logging->at_level(3);

    # Clean props from array form

    foreach my $key (qw(active submitted common id replaces source
                        read_access write_access subj pred valtype
                        implicit value obj arc_weight arc_weight_last ))
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

    my( @fields, @values, @bindtype );

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
    my $pred = RDF::Base::Pred->get( $props->{'pred'} );
    $pred or die "Pred missing";
    my $pred_id = $pred->id;
    my $pred_name = $pred->plain;

    $rec->{'pred'} = $pred_id;
    confess "Invalid pred $pred_id" if $pred_id < 1;


    push @fields, 'pred';
    push @values, $rec->{'pred'};


    ##################### subj
    my $subj;
    if( my $subj_label = $props->{'subj'} )
    {
	$subj = RDF::Base::Resource->get( $subj_label );

	unless( defined $subj )
	{
	    confess "No node '$subj_label' found";
	}

	if( UNIVERSAL::isa $subj, "RDF::Base::Literal" )
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
	$valtype = RDF::Base::Resource->get( $props->{'valtype'} );
    }
    elsif( not defined $props->{'valtype'} )
    {
	if( UNIVERSAL::isa( $props->{'value'}, "RDF::Base::Literal" ) )
	{
	    $valtype = $props->{'value'}->this_valtype;
	}
	else
	{
	    $valtype = $pred->valtype;
	}
    }
    # Setting up the final valtype below


    ##################### updated_by
    my $updated_by;
    if( $props->{'created_by'} )
    {
	$updated_by = RDF::Base::Resource->
	  get($props->{'created_by'});
	$rec->{'created_by'} = $updated_by->id;
    }
    elsif( $req and $req->user )
    {
	$updated_by = $req->user;
	$rec->{'created_by'} = $updated_by->id;
    }
    else
    {
	$updated_by = RDF::Base::Resource->get_by_label('root');
	$rec->{'created_by'} = $updated_by->id;
    }
    push @fields, 'created_by';
    push @values, $rec->{'created_by'};


    ##################### updated
    my $updated;
    if( $props->{'created'} )
    {
	$updated = RDF::Base::Literal::Time->
	  get($props->{'created'});
    }
    elsif( $args->{'updated'} )
    {
	$updated = RDF::Base::Literal::Time->
	  get($args->{'updated'});
    }
    else
    {
	$updated = now();
    }

    $rec->{'updated'} = $dbix->format_datetime( $updated );
    push @fields, 'updated';
    push @values, $rec->{'updated'};

    $rec->{'created'} = $rec->{'updated'};
    push @fields, 'created';
    push @values, $rec->{'created'};


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


    ##################### range_card_max_check
    unless( $props->{'replaces'} or $args->{'ignore_card_check'} )
    {
        if( my $rcm = $pred->first_prop('range_card_max')->plain )
        {
            my $cnt = $subj->count($pred,'solid');
            if( $cnt >= $rcm )
            {
                throw('validation', sprintf 'Cardinality check of arc failed. %s already has %d arcs with pred %s', $subj->sysdesig, $cnt, $pred->desig)
            }
        }
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
	debug "No coltype found: ".datadump(\%RDF::Base::Literal::Class::COLTYPE_valtype2name);
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

	$value_obj = RDF::Base::Resource->get_by_id( $obj_id );
    }
    elsif( not $valtype ) # Special valtype for removals
    {
	$value_obj = is_undef;
    }
    else
    {
	# It's possible we are creating an arc with an undef value.
	# That is allowed!

	debug sprintf("parsing value %s", $props->{'value'}) if $DEBUG;

	# Returns is_undef if value undef and coltype is obj
	$value_obj = RDF::Base::Resource->
	  get_by_anything( $props->{'value'},
			   {
			    %$args,
			    valtype => $valtype,
			    subj_new => $subj,
			    pred_new => $pred,
			   });

	debug sprintf("value_obj is now %s",$value_obj->sysdesig) if $DEBUG;

	if( UNIVERSAL::isa( $value_obj, 'RDF::Base::Literal' ) )
	{
	    if( my $vnode = $value_obj->node )
	    {
		# Let given value_node override that of the value
		$props->{'value_node'} ||= $vnode;

		if( $props->{'replaces'} )
		{
		    my $repl = RDF::Base::Arc->get( $props->{'replaces'} );
		    unless( $repl->obj->equals( $vnode ) )
		    {
			cluck sprintf "Replacing %s with %s for %s", $repl, $vnode, $value_obj;
		    }
		}
		else
		{
		    # The literal value must only exist in ONE (active) place

		    debug "Existing: ".$vnode->sysdesig;
		    debug "New  obj: ".$value_obj->sysdesig;
		    debug "IGNORING VALUE";

		    # We use the value_node and sets the value to undef here
		    $value_obj = is_undef;
		}
	    }
	}


	if( $value_obj->defined )
	{
	    # Coltype says how the value should be stored.  The predicate
	    # specifies the coltype.

	    # Sanity check
	    #
	    if( $coltype eq 'obj' )
	    {
		unless( UNIVERSAL::isa($value_obj, 'RDF::Base::Resource' ) )
		{
		    confess "Value incompatible with coltype $coltype: ".
		      datadump($props, 2);
		}
	    }
	    elsif( UNIVERSAL::isa($value_obj, 'RDF::Base::Resource' ) )
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
#		    $value = $value_obj->literal;

		    # Changed from literal() to plain() since
		    # literal() fro email address objects, do not
		    # stringify to the original strin
		    #
		    $value = $value_obj->plain;

		    debug 2, sprintf "Plain value is %s", (defined $value?"'$value'":'<undef>');

		    if( $coltype eq 'valtext' )
		    {
			$rec->{'valclean'} = valclean( $value );

			if( $rec->{'valclean'} =~ /^rdfbase.*hash/ )
			{
			    die "Object stringification ".datadump($rec, 2);
			}

			push @fields, 'valclean';
			push @values, $rec->{'valclean'};
		    }
                    elsif( $coltype eq 'valfloat' )
                    {
                        confess "No number  $value" unless looks_like_number($value);
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
	    if( $coltype eq 'valbin' )
	    {
		$bindtype[$#values] = PG_BYTEA;
	    }

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

	my $vnode = RDF::Base::Resource->get_by_anything($vnode_in);
	push @fields, 'obj';
	push @values, $vnode->id;
	$rec->{'obj'} = $vnode->id;
    }


    # Do not create duplicate arcs.  Check if arc with subj, pred, val
    # already exists. This checks if the arc already is existing. It
    # doesn't match on other properties. ( TODO: Also consider the
    # read_access value.)

    my $do_check = 1;
    if( $args->{'arc_create_check'} )
    {
	unless( $args->{'arc_create_check'}{ $value_obj->id } )
	{
	    $do_check = 0;
	}
    }

    if( $do_check )
    {
	my $subj = RDF::Base::Resource->get_by_id( $rec->{'subj'} );
	my $pred = RDF::Base::Pred->get( $rec->{'pred'} );


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

	    # undef weight is not the same as weight 0, but treat them
	    # as the same in this check
	    #
            my $rec_weight = $props->{'arc_weight'}||0;
	    next if $rec_weight != ($arc->weight||0);

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
		    $arc->mark_updated($updated, $updated_by);
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
		    $arc->activate({updated=>$updated});
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
		    $arc->mark_updated($updated,$updated_by);
		}

                if( $props->{'arc_weight_last'} )
                {
                    $arc->set_weight(0, {%$args,arc_weight_last=>1});
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


    ##################### valtype

    if( $valtype )
    {
	$rec->{'valtype'} = $valtype->id;
    }
    else # Special valtype for REMOVAL arc
    {
	$rec->{'valtype'} = 0;
    }

    push @fields, 'valtype';
    push @values, $rec->{'valtype'};


    ##################### arc_weight
    if( $props->{'arc_weight'} )
    {
	$rec->{'weight'}  = $props->{'arc_weight'};
    }
    push @fields, 'weight';
    push @values, $rec->{'weight'};


    #####################

#    cluck "Would have created new arc..."; return is_undef; ### DEBUG

    my $fields_part = join ",", @fields;
    my $values_part = join ",", map "?", @fields;
    my $st = "insert into arc($fields_part) values ($values_part)";
    my $sth = $dbix->dbh->prepare($st);
    debug sprintf "SQL %s (%s)", $st, join ',', map {defined($_)? $_ : 'null'} @values if $DEBUG;

    ### Binding SQL datatypes to values
    for(my$i=0;$i<=$#bindtype;$i++)
    {
	next unless $bindtype[$i];
	$sth->bind_param($i+1, undef, { pg_type => $bindtype[$i] } );
    }

    $sth->execute( @values );
    $RDF::Base::Resource::TRANSACTION{ $rec->{'ver'} } = $Para::Frame::REQ;

    my $arc = $this->get_by_rec($rec,
				{
				 subj => $subj,
				 value => $value_obj,
				});

    if( $arc->active and $props->{'arc_weight_last'} )
    {
        $arc->set_weight(0, {%$args,arc_weight_last=>1}); # Trigger resort
    }

    # If the arc was requested to be cerated active, but wasn't
    # becasue it was replacing another arc, we will activate it now

    if( $props->{'active'} and not $arc->active )
    {
	# Arc should have been submitted instead. But it might have
	# been deactivated during a resort or other operation.
        #
	$arc->activate({%$args, updated=>$updated}) if $arc->submitted;
    }


    # Sanity check
    if( $subj and $subj->id != $arc->subj->id )
    {
	confess "Creation of arc $arc->{id} resulted in confused subj: ".
	  datadump($subj,2).datadump($arc->subj,2);
    }
    if( $value_obj and not $value_obj->equals($arc->{'value'}) )
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

    $RDF::Base::Cache::Changes::Added{$arc->id} ++;

    $res->changes_add;
    if( $arc->active )
    {
	$arc->notify_change( $args );
    }
    else
    {
	$res->add_newarc( $arc );
    }

    return $arc;
}


#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

##############################################################################

=head2 subj

  $a->subj

Returns: The subject L<RDF::Base::Resource> of the arc

=cut

sub subj
{
    my( $arc ) = @_;
    # We use the subj for determining if the arc is removed or not
    return $arc->{'subj'} || is_undef;
}


##############################################################################

=head2 pred

  $a->pred

Returns: The L<RDF::Base::Pred> of the arc

=cut

sub pred
{
    my( $arc ) = @_;
    return $arc->{'pred'} || is_undef ;
}


##############################################################################

=head2 value

  $a->value

  $a->value( \%args )

Returns: The L<RDF::Base::Node> value as a L<RDF::Base::Resource>,
L<RDF::Base::Literal> or L<RDF::Base::Undef> object.  NB! Used
internally.

The property C<value> has special handling in its dynamic use for
resourcess.  This means that you can only use this method as an ordinary
method call.  Not dynamicly from TT.

Rather use L</desig>, L</loc> or L</plain>.

=cut

sub value
{
    # Two steps for handling (ignoring) broken nodes
    # Check might occure in the middle of removal/change
    my $vn = $_[0]->value_node;
    return $vn->is_value_node ? $vn->first_literal($_[1]) : $_[0]->{'value'};
}


##############################################################################

=head2 value_node

  $a->value_node

Returns the common literal resource representing the literal. Assumes
to only be called for literal arcs. Will always return the obj field.

=cut

sub value_node
{
#    debug "Getting value node $_[0]->{id}: ".($_[0]->{'value_node'}||'<undef>');
    return( $_[0]->{'value_node_obj'} ||= $_[0]->{'value_node'}
	    ? RDF::Base::Resource::Literal->get($_[0]->{'value_node'})
	    : is_undef );
}


##############################################################################

=head2 set_value_node

  $a->set_value_node()

  $a->set_value_node( $node )

Caller should do the authorization checks

=cut

sub set_value_node
{
    my( $arc, $node, $args_in ) = @_;

    $node ||= RDF::Base::Resource::Literal->get('new');

    my $st = "update arc set obj=? where ver=?";
    my $sth = $RDF::dbix->dbh->prepare($st);
    $sth->execute( $node->id, $arc->id );
    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;

    $arc->{'value_node'} = $node->id;
    $arc->{'value_node_obj'} = $node;

    my $class = "RDF::Base::Resource::Literal";
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

	debug 1, "Blessing node $node->{id} to $class";
	bless $node, $class;
    }

    return $node->init;
}


##############################################################################

=head2 obj

  $a->obj

Returns: The object L<RDF::Base::Resource> of the arc.

If the arc points to a literal resource (value node), we will return
the value node. Thus. You can't use this to determine if the arc ponts
to a literal or not. Returns L<RDF::Base::Undef> if nothing else.

For determining if the arc points at an obj, use L</objtype>.

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


##############################################################################

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


##############################################################################

=head2 value_as_html

  $a->value_as_html

A designation of the value, in HTML.

This will use L<RDF::Base::Resource/as_html> or any other
implementation of C<as_html> for the value.

For C<removals>, The deleted value will be displayd with a
line-through.

We method is placed in Arc rather than in Literal or other place since
we display the html in the context of the arc status.

=cut

sub value_as_html
{
    my( $arc, $args ) = @_;

    if( $args ){ debug "  with args ".query_desig($args);}

    my $out;
    if( $arc->is_removal )
    {
	$out = '<span style="text-decoration:line-through;color:red">';
	$out .= $arc->replaces->value_as_html($args);
	$out .= '</span>';
    }
    else
    {
	$out = $arc->value->as_html($args);
    }

    return $out;
}


##############################################################################

=head2 value_diff_as_html

  $a->value_diff_as_html

A designation of the value, in HTML.

This will use L<RDF::Base::Resource/as_html> or any other
implementation of C<as_html> for the value.

For C<removals>, The deleted value will be displayd with a
line-through.

We method is placed in Arc rather than in Literal or other place since
we display the html in the context of the arc status.

=cut

sub value_diff_as_html
{
    my( $arc, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my( $from ) = $args->{'from'};
#    debug "Diff from ".ref($from);

    my $out;
    if( $arc->is_removal )
    {
	$out = '<span style="text-decoration:line-through;color:red">';
	$out .= $arc->replaces->value_as_html( $args );
	$out .= '</span>';
    }
    elsif( my $repl = $arc->replaces )
    {
	if( $from )
	{
	    $repl = $arc->version_by_date( $from );
	}

	if( $repl )
	{
	    my $old = $repl->value( $args );
	    my $new = $arc->value( $args );

	    $out = $new->diff_as_html({%$args, old=>$old});
	}
    }

    $out ||= $arc->value->as_html( $args );

    return $out;
}


##############################################################################

=head2 value_desig

  $a->value_desig

A designation of the value, suitable for admin interface

=cut

sub value_desig
{
    my( $arc, $args ) = @_;

    if( $arc->objtype )
    {
	return $arc->obj->desig($args);
    }
    else
    {
	my $value = $arc->value || is_undef->as_string;
	return sprintf("'%s'", truncstring($value));
    }
}


##############################################################################

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


##############################################################################

=head2 created

  $a->created

Returns: The time as an L<RDF::Base::Literal::Time> object, or
L<RDF::Base::Undef>.

=cut

sub created
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_created_obj'} )
    {
	return $arc->{'arc_created_obj'};
    }

    return $arc->{'arc_created_obj'} =
      RDF::Base::Literal::Time->get( $arc->{'arc_created'} );
}


##############################################################################

=head2 created_iso8601

  $a->created_iso8601

PostgreSQL seems to always return times in the current local timezone,
regardless of timezone used to store the date. This makes it useful
for sorting and comparison. It also uses space to separate date and
time.

Returns: The time as a string in ISO 8601 format, or undef

=cut

sub created_iso8601
{
    return $_[0]->{'arc_created'} ||=
      $RDF::dbix->format_datetime( $_[0]->{'arc_created_obj'} );
}


##############################################################################

=head2 updated

  $a->updated

Returns: The time as an L<RDF::Base::Literal::Time> object, or
L<RDF::Base::Undef>.

=cut

sub updated
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_updated_obj'} )
    {
	return $arc->{'arc_updated_obj'};
    }

    return $arc->{'arc_updated_obj'} =
      RDF::Base::Literal::Time->get( $arc->{'arc_updated'} );
}


##############################################################################

=head2 updated_iso8601

  $a->updated_iso8601

PostgreSQL seems to always return times in the current local timezone,
regardless of timezone used to store the date. This makes it useful
for sorting and comparison. It also uses space to separate date and
time.

Returns: The time as a string in ISO 8601 format, or undef

=cut

sub updated_iso8601
{
    return $_[0]->{'arc_updated'} ||=
      $RDF::dbix->format_datetime( $_[0]->{'arc_updated_obj'} );
}


##############################################################################

=head2 mark_updated

  $a->mark_updated

  $a->mark_updated( $time )

Sets the update time to given time or now.

Returns the new time as a L<RDF::Base::Literal::Time>

=cut

sub mark_updated
{
    my( $arc, $time_in ) = @_;

    $time_in ||= now();
    my $time = RDF::Base::Literal::Time->get($time_in);

    my $dbix = $RDF::dbix;
    my $date_db = $dbix->format_datetime($time);
    my $st = "update arc set updated=? where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );
    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;

    $arc->{'arc_updated'} = $date_db;
    return $arc->{'arc_updated_obj'} = $time;
}


##############################################################################

=head2 activated

  $a->activated

Returns: The time as an L<RDF::Base::Literal::Time> object, or
L<RDF::Base::Undef>.

=cut

sub activated
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_activated_obj'} )
    {
	return $arc->{'arc_activated_obj'};
    }

    return $arc->{'arc_activated_obj'} =
      RDF::Base::Literal::Time->get( $arc->{'arc_activated'} );
}


##############################################################################

=head2 deactivated

  $a->deactivated

Returns: The time as an L<RDF::Base::Literal::Time> object, or
L<RDF::Base::Undef>.

=cut

sub deactivated
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_deactivated_obj'} )
    {
	return $arc->{'arc_deactivated_obj'};
    }

    return $arc->{'arc_deactivated_obj'} =
      RDF::Base::Literal::Time->get( $arc->{'arc_deactivated'} );
}


##############################################################################

=head2 deactivated_by

  $a->deactivated_by

Returns: The L<RDF::Base::Resource> of the deactivator, or
L<RDF::Base::Undef>.

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

    my $dbh = $RDF::dbix->dbh;
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


##############################################################################

=head2 unsubmitted

  $a->unsubmitted

NB: This is not the reverse of L</submitted>

C<unsubmitted> means that the submission has been taken back.  The
date of the submission is the L</updated> time, if the L</submitted>
flag is set.

Returns: The time as an L<RDF::Base::Literal::Time> object, or
L<RDF::Base::Undef>.

=cut

sub unsubmitted
{
    my( $arc ) = @_;
    if( defined $arc->{'arc_unsubmitted_obj'} )
    {
	return $arc->{'arc_unsubmitted_obj'};
    }

    return $arc->{'arc_unsubmitted_obj'} =
      RDF::Base::Literal::Time->get( $arc->{'arc_unsubmitted'} );
}


##############################################################################

=head2 updated_by

  $a->updated_by

See L</created_by>

=cut

sub updated_by
{
    return $_[0]->created_by;
}


##############################################################################

=head2 activated_by

  $a->activated_by

Returns: The L<RDF::Base::Resource> of the activator, or
L<RDF::Base::Undef>.

=cut

sub activated_by
{
    my( $arc ) = @_;
    return $arc->{'activated_by_obj'} ||=
      $Para::Frame::CFG->{'user_class'}->get( $arc->{'activated_by'} ) ||
	  is_undef;
}


##############################################################################

=head2 created_by

  $a->created_by

Returns: The L<RDF::Base::Resource> of the creator, or
L<RDF::Base::Undef>.

=cut

sub created_by
{
    my( $arc ) = @_;
    return $arc->{'arc_created_by_obj'} ||=
      $Para::Frame::CFG->{'user_class'}->get( $arc->{'arc_created_by'} ) ||
	  is_undef;
}


##############################################################################

=head2 version_id

  $a->version_id

=cut

sub version_id
{
    return $_[0]->{'id'};
}


##############################################################################

=head2 replaces_id

  $a->replaces_id

=cut

sub replaces_id
{
    return $_[0]->{'replaces'};
}


##############################################################################

=head2 replaces

  $a->replaces

=cut

sub replaces
{
    return RDF::Base::Arc->get_by_id($_[0]->{'replaces'});
}


##############################################################################

=head2 source

  $a->source

=cut

sub source
{
    my( $arc ) = @_;
    return $arc->{'source_obj'} ||=
      RDF::Base::Resource->get( $arc->{'source'} );
}


##############################################################################

=head2 read_access

  $a->read_access

=cut

sub read_access
{
    my( $arc ) = @_;
    return $arc->{'arc_read_access_obj'} ||=
      RDF::Base::Resource->get( $arc->{'arc_read_access'} );
}


##############################################################################

=head2 write_access

  $a->write_access

=cut

sub write_access
{
    my( $arc ) = @_;
    return $arc->{'arc_write_access_obj'} ||=
      RDF::Base::Resource->get( $arc->{'arc_write_access'} );
}


##############################################################################

=head2 is_owned_by

  $a->is_owned_by( $agent )

C<$agent> must be a Resource. It may be a L<RDF::Base::User>.

Returns: true if C<$agent> is regarded as an owner of the arc

TODO: Handle arcs where subj and obj has diffrent owners

TODO: Handle user that's members of a owner group

See: L<RDF::Base::Resource::is_owned_by>

=cut

sub is_owned_by
{
    my( $arc, $agent ) = @_;

    if( UNIVERSAL::isa($agent, 'RDF::Base::User') )
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


##############################################################################

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


##############################################################################

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


##############################################################################

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


##############################################################################

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


##############################################################################

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


##############################################################################

=head2 weight

  $a->weight

Returns: the arc weight

May be undef

=cut

sub weight
{
    return $_[0]->{'arc_weight'};
}


##############################################################################

=head2 arc_weight

  $a->arc_weight

The same as L</weight>

=cut

sub arc_weight
{
    return $_[0]->{'arc_weight'};
}


##############################################################################

=head2 distance

  $a->distance

Returns: The number of arcs that inferes this arc

=cut

sub distance
{
    my( $arc ) = @_;
    if( not $arc->{'indirect'} )
    {
	return 0;
    }

    if( $RDF::Base::IN_STARTUP )
    {
	return 1; # Avoids bootsrap recursion
    }

#    debug "Checking distance of ".$arc->sysdesig;

    unless( @{$arc->{'explain'}} )
    {
	$arc->validate_check;

	# indirect status may have been corrected by validate_check
	if( not $arc->{'indirect'} )
	{
	    return 0;
	}
    }

    my $expl = $arc->{'explain'}[0];
#    die datadump($expl,1) unless ref $expl->{'a'} eq 'RDF::Base::Arc';
#    die datadump($expl,1) unless ref $expl->{'b'} eq 'RDF::Base::Arc';

    unless( ref($expl->{'a'}) and ref($expl->{'b'}) )
    {
	confess datadump([$expl,\@_], 3);
    }

    return( 1 + $expl->{'a'}->distance + $expl->{'b'}->distance );

}


##############################################################################

=head2 active

  $a->active

Returns: true if this arc is active

=cut

sub active
{
    return $_[0]->{'active'};
}


##############################################################################

=head2 inactive

  $a->inactive

Returns: true if this arc is inactive

=cut

sub inactive
{
    return not $_[0]->{'active'};
}


##############################################################################

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


##############################################################################

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


##############################################################################

=head2 old

  $a->old

This is a arc that has been deactivated.

Returns: true if this arc is old

=cut

sub old
{
    return( $_[0]->{'arc_deactivated'} );
}


##############################################################################

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

    my $dbh = $RDF::dbix->dbh;
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


##############################################################################

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

    my $dbh = $RDF::dbix->dbh;
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


##############################################################################

=head2 version_by_date

  $a->version_by_date

May return undef;

See also L<RDF::Base::Arc::List/arc_active_on_date>

Returns: The arc that was active at the given time.

=cut

sub version_by_date
{
    my( $arc, $time ) = @_;
    my $class = ref($arc);

    my $paarc;

    my $dbh = $RDF::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? and activated <= ? and (deactivated > ? or deactivated is null)");

    my $time_str = $RDF::dbix->format_datetime( $time );
    $sth->execute($arc->common_id, $time_str, $time_str );
    if( my $arc_rec = $sth->fetchrow_hashref )
    {
	$paarc = $class->get_by_rec( $arc_rec );
    }
    $sth->finish;

    # May be undef
    return $paarc;
}


##############################################################################

=head2 versions

  $a->versions( $proplim, $args )

Returns: A L<RDF::Base::list> of all versions of this arc

TODO: Make this a non-materialized list

=cut

sub versions
{
    my( $arc, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

#    debug "Getting versions of $arc->{id} with arclim ".$arclim->sysdesig;

    my $class = ref($arc);

    my @arcs;

    my $dbh = $RDF::dbix->dbh;
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

    return RDF::Base::Arc::List->new(\@arcs);
}


##############################################################################

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

    my $dbh = $RDF::dbix->dbh;
    my $sth = $dbh->prepare("select * from arc where id=? and replaces=?");
    $sth->execute($arc->common_id, $arc->id);
    while( my $arc_rec = $sth->fetchrow_hashref )
    {
	push @list, $class->get_by_rec( $arc_rec );
    }
    $sth->finish;

    return RDF::Base::Arc::List->new(\@list);
}


##############################################################################

=head2 common

  $a->common

TODO: Should be it's own class

Returns: The node representing the arc, regardless of version

=cut

sub common
{
    return $_[0]->{'common'} ||=
      RDF::Base::Resource->get_by_id($_[0]->{'common_id'});
}


##############################################################################

=head2 common_id

  $a->common_id

TODO: Should be it's own class

Returns: The node id representing the arc, regardless of version

=cut

sub common_id
{
    return $_[0]->{'common_id'};
}


##############################################################################

=head2 desig

  $a->desig( \%args )

Returns: a plain string representation of the arc

=cut

sub desig
{
    my( $arc, $args ) = @_;

    return sprintf("%s --%s--> %s", $arc->subj->desig($args), $arc->pred->plain, $arc->value_desig($args));
}


##############################################################################

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


##############################################################################

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


##############################################################################

=head2 table_row

  $a->table_row

=cut

sub table_row
{
    my( $arc, $args ) = @_;

    my $out = "<tr>";

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
#    my $out = '';
#    my $is_scof = $args->{'range_scof'};
    my $is_rev = ( $args->{'rev'} ? 'rev' : '' );
#    my $is_pred = ( $is_scof ? 'scof' : 'is' );
#    my $range = $args->{'range'} || $args->{'range_scof'};
    my $ajax = ( defined $args->{'ajax'} ? $args->{'ajax'} : 1 );
    my $divid = $args->{'divid'};
    my $disabled = $args->{'disabled'} || 0;
    my $subj_id = $args->{'source'}->id;
#    my $hide_create_button = $args->{'hide_create_button'} || 0;

    my $check_subj = $arc->subj;
    my $item = $arc->value;

#    debug "table row for ".$arc->sysdesig;
#    debug query_desig $args;


    foreach my $col ( @{$args->{'columns'}} )
    {
	$out .= "<td>";
	given( $col )
	{
	    when('-arc_remove')
	    {
		unless( $disabled )
		{
		    if( $ajax )
		    {
			return '' unless $req->session->{'advanced_mode'};
			
			my $arc_id = $arc->id;
			my $onclick = "rb_remove_arc('$divid',$arc_id,$subj_id)";
		
			$out .= "<button onclick=\"$onclick\" class=\"no_button nopad trash\" title=\"Delete\"><i class=\"fa fa-trash-o\"></i></button>";
		    }
		    else
		    {
			my $field = RDF::Base::Widget::build_field_key({arc => $arc});
			$out .= Para::Frame::Widget::hidden('check_arc_'. $arc->id, 1);
			$out .= Para::Frame::Widget::checkbox($field, $item->id, 1);
		    }
		    $out .= " ";
		}
	    }

	    when('-arc_updated')
	    {
		$out .= $arc->updated;
	    }

	    when('-arc_seen_status')
	    {
		die "not implemented" if $is_rev;
		if( $check_subj->first_arc('unseen_by',$item) )
		{
		    if( my $seen = $check_subj->first_arc('seen_by',$item) )
		    {
			$out .= "last seen ".$seen->updated;
		    }
		    else
		    {
			$out .= "never seen";
		    }
		}
		elsif( $check_subj->first_arc('seen_by',$item) )
		{
		    $out .= "up to date";
		}
	    }

	    when('desig')
	    {
		if( $disabled )
		{
		    $out .= ( $is_rev ? $check_subj->wu_jump :
			      $item->wu_jump );
#		    $out .= ( $is_rev ? $check_subj->desig($args) :
#			      $item->desig($args) );
		}
		else
		{
		    if( my $item_prefix = $args->{'item_prefix'} )
		    {
			$out .= $item->$item_prefix." ";
		    }
		    $out .= ( $is_rev ? $check_subj->wu_jump :
			      $item->wu_jump );
		}
		$out .= '&nbsp;' . $arc->edit_link_html;
	    }

	    default
	    {
#		debug "Calling method $col ($is_rev) on node ".$item->sysdesig;

#		debug query_desig($args);
		my $val = ( $is_rev ? $check_subj->$col() : $item->$col() );
#		my $val = $item->weight($args);
#		debug "  got ".query_desig($val);

		$out .= $val;
	    }
	}
	$out .= "</td>";
    }

    $out .= "</tr>\n";

    return $out;
}


##############################################################################

=head2 syskey

  $a->syskey

Returns: a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("arc:%d", shift->{'id'});
}


##############################################################################

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


##############################################################################

=head2 is_removal

  $a->is_removal

Is this an arc version representing the deletion of an arc?

Returns: 1 or 0

=cut

sub is_removal
{
    return $_[0]->{'valtype'} ? 0 : 1;
}


##############################################################################

=head2 is_arc

  $a->is_arc

Returns: 1

=cut

sub is_arc
{
    1;
}


##############################################################################

=head2 objtype

  $a->objtype

Returns: true if the L</coltype> of the L</value> is C<obj>.

=cut

sub objtype
{
    return 1 if $_[0]->coltype eq 'obj';
    return 0;
}


##############################################################################

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
    return RDF::Base::Literal::Class->coltype_by_valtype_id_or_obj( $_[0]->{'valtype'} );
}


##############################################################################

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
	return RDF::Base::Resource->get( $_[0]->{'valtype'} );
    }
    else
    {
	return is_undef;
    }
}


##############################################################################

=head2 this_valtype

  $a->this_valtype

This would be the same as the C<is> property of this resource. But it
must only have ONE value. It's important for literal values.

This method will return the literal valtype for value resoruces.

See also: L<RDF::Base::Literal/this_valtype>, L</is_value_node>.

Returns: The C<arc> class resource.

=cut

sub this_valtype
{
    return RDF::Base::Resource->get_by_label('arc');
}


##############################################################################

=head2 explain

  $a->explain( \%args )

Explains how this arc has been infered.

Returns: reference to a list of hashes with the keys 'a', 'b' and 'c'
pointing to the two arcs used in the inference and this resulting arc.
The key 'rule' points to the rule used for the inference.

The list will be empty if this is'nt an infered arc.

... May remove arcs makred as L</indirect> if they arn't L</explict>.

The explain hash is set up by L<RDF::Base::Rule/validate_infere>.

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

##############################################################################

=head2 deactivate

  $a->deactivate( $arc, $args )

Must give the new active arc as arg. This will be called by
L</activate> or by L</remove>.

Only active or submitted arcs can be deactivated.

Submitted arcs are not active but will be handled here. It will be
deactivated as is if it was active, since its been replaced by a new
arc.

The given new active arc would have triggered a L</notify_change>,
rather than this method.

Returns: nothing

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
    my $dbix = $RDF::dbix;
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, deactivated=?, active='false', submitted='false' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $date_db, $arc->id );
    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;

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
    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;

    $args->{'res'}->changes_add;

    debug 1, "Deactivated id ".$arc->sysdesig;

    return;
}


##############################################################################

=head2 vacuum_facet

Create or remove implicit arcs. Update implicit
status.

For ACTIVE arcs pointing at literals it will also vacuum the literal before
validating the value.

Returns: ---

=cut

sub vacuum_facet
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs( $args_in );

    # TODO: Move value cleaning to Literal classes

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


	unless( $arc->old or $arc->is_removal )
	{
	    debug "  check valtype" if $DEBUG;
	    unless( $arc->check_valtype( $args ) )
	    {
		$arc->check_value( $args );
	    }
	}

#	debug "  Reset clean";
	$arc->reset_clean($args);

	if( $arc->active )
	{
	    $arc->create_check( $args );

	    my $val = $arc->value;
	    if( $val->is_literal )
	    {
		$val->vacuum_node( $args );
	    }

	    $arc->validate_range;
	}
    }
}


##############################################################################

=head2 check_valtype

  $a->check_valtype( \%args )

Compares the arc valtype with the pred valtype

=cut

sub check_valtype
{
    my( $arc, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs( $args_in );

#    Para::Frame::Logging->this_level(3);
#    cluck "CHECK_VALTYPE";

    my $old_val = $arc->value;

    # Reset valtype cache
    $old_val->this_valtype_reset;

    my $pred = $arc->pred;
    my $arc_valtype = $arc->valtype;
    my $pred_valtype = $pred->valtype;
    # Falls back on arc_valtype in case of Undef
    my $old_valtype = $old_val->this_valtype || $arc_valtype;
    my $new_valtype;
    my $c_resource = RDF::Base::Constants->get('resource');

    if( $pred->objtype and not $old_valtype->equals($c_resource) )
    {
	$new_valtype = $old_valtype;
    }
    else
    {
	$new_valtype = $pred_valtype;
    }


    if( debug > 2 )
    {
	debug "Arc   valtype is ".$arc_valtype->sysdesig;
	debug "Pred  valtype is ".$pred_valtype->sysdesig;
	debug "Value         is ".$old_val->sysdesig;
	debug "Value valtype is ".$old_valtype->sysdesig;
	debug "New   valtype is ".$new_valtype->sysdesig;
    }


    if( $arc_valtype->equals( $new_valtype ) )
    {
#	debug "  same valtype";
	return 0;
    }
    elsif( $arc_valtype->scof( $new_valtype ) )
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
	debug "   to ".$new_valtype->sysdesig;
    }

    my $newargs =
    {
     'activate_new_arcs' => $arc->active,
     'force_set_value'   => 1,
     'force_set_value_same_version' => $arc->active,
     'valtype' => $new_valtype,
    };


    if( $arc->objtype )
    {
	if( $new_valtype->equals( $c_resource ) )
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
	    if( $old_val->is($new_valtype) )
	    {
		# Old value in range
		debug 3, "old value in range";
		$arc->set_value( $old_val, $newargs );

#		$old_val->vacuum; # Infinite recursion
	    }
	    elsif( $arc_valtype->equals($c_resource) )
	    {
		debug "TRANSLATION OF VALTYPE";
		debug "  for ".$arc->sysdesig;
		debug " from ".$arc_valtype->sysdesig;
		debug "   to ".$new_valtype->sysdesig;
		debug "Trusting new given valtype";
#		confess "or not...";
		$arc->set_value( $old_val, $newargs );
#		die "CHECKME";
	    }
	    else
	    {
		debug "TRANSLATION OF VALTYPE";
		debug "  for ".$arc->sysdesig;
		debug " from ".$arc_valtype->sysdesig;
		debug "   to ".$new_valtype->sysdesig;

		$Para::Frame::REQ->session->set_debug(3);
		# Reset valtype cache
		$old_val->{'valtype'} = undef;
		debug "val valtype: ".$old_val->this_valtype->sysdesig;


		confess "FIXME";
	    }
	}
	else # literal
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
	else # literal
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


##############################################################################

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


##############################################################################

=head2 reset_clean

  $a->reset_clean

Sets L<RDF::Base::Literal::String/clean> based on L</value>, if it's a
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
	    my $dbh = $RDF::dbix->dbh;
	    my $sth = $dbh->prepare
	      ("update arc set valclean=? where ver=?");
#	    die if $cleaned =~ /^rdfbase/;
	    $sth->execute($cleaned, $arc->version_id);
	    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;
	    $arc->{'clean'} = $cleaned;

	    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;

	    $res->changes_add;
	}
    }
}


##############################################################################

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
    my $changed = 0;
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
		$changed += $rarc->remove({%$args, force=>1});
	    }
	}

	$changed += $arc2->remove({%$args, force=>1});
    }

    # Reconstitute node status
    #
    if( $changed )
    {
	debug "Reconstituting arc ".$arc->sysdesig;
	$arc->register_with_nodes;
	$arc->schedule_check_create( $args );
    }
}


##############################################################################

=head2 has_value

  $a->has_value( $val, \%args )

  $a->has_value({ $pred => $value }, \%args )

If given anything other than a hashref, calls
L<RDF::Base::Object/matches> and returns the result.

In the special case of negated pred matches:
  $a->has_value({ ${pred}_ne => [ $val1, $val2, ... ]}, \%args)

Instead of the normal OR logic:
  if( ($prop ne $val1) or ($prop ne $val2) ...

We will use AND:
  if( ($prop ne $val1) and ($prop ne $val2) ...

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

    my $valtype;

    if( $pred_name eq 'value' )
    {
	return $arc->value_equals($value, $args_in);
    }

    #
    #
    ##### TODO: Move all of the below to SUPER::has_value !!!
    #
    #

    elsif( my $valtype_name = $DYNAMIC_PRED{ $pred_name } )
    {
	$target = $arc->$pred_name();
	$valtype = RDF::Base::Resource->get_by_label($valtype_name);

#	debug "has_value TARGET is ".$target->sysdesig;
    }
    else
    {
	return $arc->SUPER::has_value($val_in, $args);
    }

    my $args_valtype =
    {
     %$args,
     valtype => $valtype,
    };
    my $R = RDF::Base->Resource;

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
	$value = RDF::Base::List->new($value);
    }

    if( UNIVERSAL::isa( $value, 'Para::Frame::List' ) )
    {
	my $match = $args->{'match'} || 'eq';
	if( $match eq 'ne' ) ### SPECIAL CASE; INVERT LOGIC
	{
	    $args->{'match'} = 'eq';
	    my( $val_in, $error ) = $value->get_first;
	    while(! $error )
	    {
		my $val_parsed = $R->get_by_anything($val_in, $args_valtype);
		return 0 if $target->matches( $val_parsed, $args );
	    }
	    continue
	    {
		( $val_in, $error ) = $value->get_next;
	    };
	    return $arc;
	}

	my( $val_in, $error ) = $value->get_first;
	while(! $error )
	{
	    my $val_parsed = $R->get_by_anything($val_in, $args_valtype);
#	    my $match = $args->{'match'} || 'eq';
#	    debug sprintf "CHECKS %d if %s %s %s ", $arc->id, $target->sysdesig, $match, ,query_desig($val_parsed);

	    return $arc if $target->matches( $val_parsed, $args );
#	    debug "  no match";
	}
	continue
	{
	    ( $val_in, $error ) = $value->get_next;
	};
	return 0;
    }


    my $val_parsed = $R->get_by_anything($value, $args_valtype);

#    my $match = $args->{'match'} || 'eq';
#    debug sprintf "CHECKS %d %s if %s %s %s ", $arc->id, $pred_name, $target->sysdesig, $match, ,query_desig($val_parsed);
#    debug " 1. ".datadump($target,1);
#    debug " 2. ".datadump($val_parsed,1);
#    debug datadump($arc,1);

    return $arc if $target->matches( $val_parsed, $args );
#    debug "  no match";
    return 0;
}


##############################################################################

=head2 value_equals

  $a->value_equals( $val, \%args )

Supported args are

  match
  clean
  arclim

Default C<$match> is C<eq>. Other supported values are C<ne>, C<gt>, C<lt>, C<begins> and C<like>.

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

    if( $DEBUG )
    {
        debug "Compares arc ".$arc->id." with ".query_desig($val2);
    }


    if( $arc->objtype ) # Might be REMOVAL arc
    {
	if( $DEBUG )
	{
	    debug "Comparing values:";
	    debug "1. ".$arc->obj->safedesig;
	    debug "2. ".query_desig($val2);
	}

	if( $match eq 'eq' )
	{
	    return $arc->obj->equals( $val2, $args );
	}
	elsif( $match eq 'ne' )
	{
	    return not $arc->obj->equals( $val2, $args );
	}
	elsif( $match eq 'gt' )
	{
	    return( $arc->obj > $val2 );
	}
	elsif( $match eq 'lt' )
	{
	    return( $arc->obj < $val2 );
	}
	elsif( ($match eq 'begins') or ($match eq 'like') )
	{
	    return 0;
	}
	else
	{
	    confess "Matchtype $match not implemented";
	}
    }
    elsif( ref $val2 eq 'RDF::Base::Resource' )
    {
	debug "  A normal resource is compared with a Literal" if $DEBUG;

	# It seems that the value of the arc is a literal.  val2 is a
	# node. They are not equal.

	return 0;
    }
    else
    {
        my $val1 = $arc->value;
        my $coltype = $arc->coltype;

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
	}


        if( $coltype eq 'valfloat')
        {
            $val1 = $val1->plain;
            if( ref $val2 )
            {
                $val2 = $val2->plain;
            }
        }
        elsif( $coltype eq 'valtext' )
        {
            $val1 = $val1->plain;
            if( ref $val2 )
            {
                $val2 = $val2->plain;
            }

            if( $clean )
            {
                $val1 = valclean(\$val1);
                $val2 = valclean(\$val2);
            }
        }
        elsif( $coltype eq 'valdate' )
        {
            unless( ref $val2 )
            {
                $val2 = RDF::Base::Literal::Time->parse($val2);
            }
        }




	# This part is similar to RDF::Base::Object/matches
	#
	#

	if( $match eq 'eq' )
	{
 	    if( $coltype eq 'valfloat' )
	    {
                return( $val1 == $val2 );
            }
	    return $val1 eq $val2;
	}
	elsif( $match eq 'ne' )
	{
 	    if( $coltype eq 'valfloat' )
	    {
                return( $val1 != $val2 );
            }
	    return $val1 ne $val2;
	}
	elsif( $match eq 'begins' )
	{
	    return 1 if $val1 =~ /^\Q$val2/;
	}
	elsif( $match eq 'like' )
	{
	    return 1 if $val1 =~ /\Q$val2/;
	}
	elsif( $match eq 'gt' )
	{
	    if( $coltype eq 'valtext' )
	    {
		return $arc if $val1 gt $val2;
	    }
	    else # Anything else should have overloaded '>'
	    {
#                debug "  comparing a ".ref($val1)." with a ".ref($val2);
		return $arc if $val1 > $val2;
	    }
	}
	elsif( $match eq 'lt' )
	{
	    if( $coltype eq 'valtext' )
	    {
		return $arc if $val1 lt $val2;
	    }
	    else # Anything else should have overloaded '<'
	    {
		return $arc if $val1 < $val2;
	    }
	}
	else
	{
	    confess "Matchtype $match not implemented";
	}
    }

    return 0;
}


##############################################################################

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

	next unless RDF::Base::Arc::Lim::arc_meets_lim( $arc, $_ );



#	debug "    passed";
	return 1;
    }

#    debug "    failed";
    return 0;
}


##############################################################################

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

    if( my $val = $arc->value )
    {
	return 1 if $val->meets_proplim($proplim, $args_in);
    }

    return 0;
}


##############################################################################

=head2 remove

  $a->remove( \%args )

Removes the arc. Will also remove arcs pointing to/from the arc itself.

An arc is removed by the activation (and deactivation) of a new
version with the value set to null and with valtype 0. That arc will
have the activation and deactivation date identical. This will keep
history about who requested the removal and who authorized it.

New (non-active) arcs can be removed directly by the authorized agent,
without the creation of a removal arc.

A forced removal will not trigger
L<RDF::Base::Resource/update_unseen_by>.


Supported args are:

  force
  force_recursive
  implicit
  res
  recursive


Default C<implicit> bool is false.

A true value means that we want to remove an L</implict> arc.

A false value means that we want to remove an L</explicit> arc.

The C<implicit> is used internally to ONLY remove arcs that's no
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

    if( $args->{'recursive'} )
    {
	return $arc->remove_recursive( $args );
    }

    my $remove_if_no_longer_implicit = $args->{'implicit'} || 0;
    my $create_removal = 0;
    my $force = $args->{'force'} || $args->{'force_recursive'} || 0;
    my $arc_id = $arc->id;

    if( $DEBUG and not $remove_if_no_longer_implicit )
    {
	debug "REQ REM ARC ".$arc->sysdesig;

	my($package, $filename, $line) = caller;
	debug "  called from $package, line $line";
	debug "  remove if no longer implicit: $remove_if_no_longer_implicit";
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

	if( ($arc->active or $arc->replaced_by->size )
	    and $arc->explicit and not $remove_if_no_longer_implicit )
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
	    if( $remove_if_no_longer_implicit )
	    {
		debug "  Arc implicit and infered" if $DEBUG > 1;
		return 0;
	    }
	    else
	    {
		# Arc was explicit but is now indirect implicit
		debug "  Arc infered; set implicit" if $DEBUG;
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
		$remove_if_no_longer_implicit ++; # Implicit remove mode
		$create_removal = 0;
	    }
	}

	if( $remove_if_no_longer_implicit and $arc->explicit ) # remove implicit
	{
	    debug "  removed implicit but arc explicit\n" if $DEBUG > 1;
	    return 0;
	}
	elsif( not $remove_if_no_longer_implicit and $arc->implicit ) # remove explicit
	{
	    debug "  Removed explicit but arc implicit\n" if $DEBUG;
	    return 0;
	}
	elsif( not $remove_if_no_longer_implicit and $arc->indirect ) # remove explicit
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

#    cluck "Forcing delete";

    # Force just first level. The infered may be dependant on other arcs
    my $args2 = {%$args, force=>0, force_recursive=>0};


#    my $mrk = Time::HiRes::time();
#    $::PRT1 += $mrk - $::MRK;
#    $::MRK = $mrk;

    debug "  remove_check" if $DEBUG;
    $arc->remove_check( $args2 );

    # May have been removed during remove_check
    return 1 if $arc->is_removed;

#    $mrk = Time::HiRes::time();
#    $::PRT2 += $mrk - $::MRK;
#    $::MRK = $mrk;

    debug "  SUPER::remove" if $DEBUG;
    $arc->SUPER::remove( $args2 );  # Removes the arc node: the arcs properties

    my $dbh = $RDF::dbix->dbh;

    debug "  remove replaced by" if $DEBUG;
    my $sth_repl = $dbh->prepare("update arc set replaces=null where replaces=?");
    foreach my $repl ( $arc->replaced_by->nodes )
    {
        $repl->{replaces} = undef;
    }
    $sth_repl->execute($arc_id);


#    $mrk = Time::HiRes::time();
#    $::PRT3 += $mrk - $::MRK;
#    $::MRK = $mrk;

    ### Not important if doesn't exist in DB. For example, if the arc
    ### was rolled back before it was comitted. We can still use this
    ### method for removing the arc from memory!

#    debug "Removed arc id ".$arc->sysdesig;

    my $sth = $dbh->prepare("delete from arc where ver=?");
    $res->changes_add;
#    debug "***** Would have removed ".$arc->sysdesig; return 1; ### DEBUG
    $sth->execute($arc_id);
    $RDF::Base::Resource::TRANSACTION{ $arc_id } = $Para::Frame::REQ;


#    $mrk = Time::HiRes::time();
#    $::PRT4 += $mrk - $::MRK;
#    $::MRK = $mrk;

    debug "  Set disregard arc $arc->{id} #$arc->{ioid}\n" if $DEBUG;
    $arc->{disregard} ++;

    $arc->deregister_with_nodes();
#    $arc->subj->reset_cache;
#    $arc->value->reset_cache(undef);

    $RDF::Base::Cache::Changes::Removed{$arc_id} ++;


#    $mrk = Time::HiRes::time();
#    $::PRT5 += $mrk - $::MRK;
#    $::MRK = $mrk;


    # Clear out data from arc (and arc in cache)
    #
    # We use the subj prop to determine if this arc is removed
    #
    # Sync with init() property setup
    debug "  clear arc data\n" if $DEBUG;
    foreach my $prop (qw(
			    subj pred value value_node clean implicit
			    indirect explain replaces source
			    arc_weight arc_weight_last active
			    submitted activated_by valtype
			    arc_created_by arc_read_access
			    arc_write_access arc_activated
			    arc_deactivated arc_created arc_updated
			    unsubmitted arc_created_obj
			    arc_updated_obj arc_activated_obj
			    arc_deactivated_obj arc_deactivated_by_obj
			    arc_unsubmitted_obj activated_by_obj
			    arc_created_by_obj source_obj
			    arc_read_access_obj arc_write_access_obj
			    value_node_obj
		       ))
    {
	delete $arc->{$prop};
    }

    # Remove arc from cache
    #
    delete $RDF::Base::Cache::Resource{ $arc_id };

    # Do not try to vacuum this
    #
    $res->{'vacuumed'}{$arc->{'id'}} ++;

    return 1; # One arc removed
}


##############################################################################

=head2 remove_recursive

  $a->remove_recursive( \%args )

Called by L</remove> if given argument C<recursive>

returns: -

=cut

sub remove_recursive
{
    my( $arc, $args ) = @_;

    my @rarcs;
    my $created_by = $arc->created_by;
    if( my $obj = $arc->obj )
    {
	@rarcs = $obj->arc_list(undef,undef,aais($args,'explicit'))->as_array;
    }

    $args->{'recursive'} = 0;
    $arc->remove( $args );
    $args->{'recursive'} = 1;

    foreach my $rarc ( @rarcs )
    {
	if( $rarc->created_by->equals( $created_by ) )
	{
	    debug 1, "Recursive removal of selected arcs";
	    $rarc->remove($args);
	}
    }
}


##############################################################################

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

    my $arc_out =  RDF::Base::Arc->create({
				   common      => $arc->common_id,
				   replaces    => $arc->id,
				   subj        => $arc->{'subj'},
				   pred        => $arc->{'pred'},
				   value       => is_undef,
				   valtype     => 0,
				  }, $args);
#    debug "Created removal arc ".$arc->sysdesig;
    return $arc_out;
}


##############################################################################

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


##############################################################################


=head2 set_value

  $a->set_value( $new_value, \%args )

Sets the L</value> of the arc.

Determines if we are dealning with L<RDF::Base::Resource> or
L<RDF::Base::Literal>.

Supported args are:

  force_set_value
  force_set_value_same_version
  valtype
  value_node

If a new arc version is created, that creation may trigger a
L</notify_change>. A foreced update will not trigger a
L</notify_change>.


Returns: the arc changed, or the same arc

=cut

sub set_value
{
    my( $arc, $value_new_in, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(4);

    debug 3, sprintf "Set value of arc %s to '%s'",
      $arc->{'id'}, ((ref $value_new_in?$value_new_in->sysdesig :
		      $value_new_in)||'<undef>');

    my $coltype_old  = $arc->coltype;
    my $value_new;
    if( $args->{'force_set_value'} ) # accept new given value
    {
	$value_new = $value_new_in;
    }
    else # lookup and validate the new given value
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
	my $value_new_list = RDF::Base::Resource->find_by_anything
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


    ### Set up new value node
    #
    my $vnode_old   = $arc->value_node;
    my $vnode_new;
    if( exists $args->{'value_node'} )
    {
	$vnode_new = RDF::Base::Resource->
	  get_by_anything($args->{'value_node'});
    }
    else
    {
	$vnode_new = $vnode_old;
    }

    if( $vnode_new )
    {
	if( UNIVERSAL::isa($value_new,'RDF::Base::Literal') )
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
    my $valtype_new;
    my $objtype_old = ($coltype_old eq 'obj')? 1 : 0;
    my $objtype_new = ($coltype_new eq 'obj')? 1 : 0;

    # Tries to mimic valtype algorithm in /create
    if( RDF::Base::Constants->get('resource')->equals($valtype_old) )
    {
        $valtype_new = $valtype_old;
    }
    elsif( $value_new->is_literal )
    {
        $valtype_new = $value_new->this_valtype;
    }
    else
    {
        $valtype_new = $arc->pred->valtype;
    }


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


    # Are there any changes to be made?
    #
    unless( $same_value and
	    $valtype_new->equals( $valtype_old ) and
	    $vnode_old->equals($vnode_new)
	  )
    {
	# Normal case: create a new version of the arc
	#
	unless( $arc->is_new or $args->{'force_set_value_same_version'} )
	{
	    my $new = RDF::Base::Arc->create({
					      common      => $arc->common_id,
					      replaces    => $arc->id,
					      subj        => $arc->{'subj'},
					      pred        => $arc->{'pred'},
					      value       => $value_new,
					      value_node  => $vnode_new,
					     }, $args );
	    return $new;
	}


	# Changing the existing arc, in place
	#
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
	my $dbix        = $RDF::dbix;
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
                confess "No number $value_db" unless looks_like_number($value_db);
	    }
	    elsif( $coltype_new eq 'valtext' )
	    {
		unless( UNIVERSAL::isa $value_new, "RDF::Base::Literal::String")
		{
		    confess "type mismatch for ".datadump($value_new,2);
		}

		$value_db = $value_new;
		my $clean = $value_new->clean_plain;

		push @dbparts, "valclean=?";
		push @dbvalues, $clean;

		$arc->{'clean'} = $clean;
	    }
	    elsif( $coltype_new eq 'valbin' )
	    {
		$value_db = $value_new;
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
	      "updated=?"
	    );

	push( @dbvalues,
	      $value_db,
	      $valtype_new->id,
	      $now_db,
	    );

#	if( $arc->is_new )
#	{
#	    push( @dbparts,
#		  "created=?",
#		  "created_by=?",
#		);
#
#	    push( @dbvalues,
#		  $now_db,
#		  $u_node->id,
#		);
#	}


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
	$RDF::Base::Resource::TRANSACTION{ $arc_id } = $Para::Frame::REQ;

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
	$RDF::Base::Cache::Changes::Updated{$arc->id} ++;
	if( $value_old->is_resource )
	{
	    $RDF::Base::Cache::Changes::Updated{$value_old->id} ++;
	}
	if( $value_new->is_resource )
	{
	    $RDF::Base::Cache::Changes::Updated{$value_new->id} ++;
	}

	debug 0, "Updated arc ".$arc->sysdesig;

	$res->changes_add;
	unless( $arc->active )
	{
	    $res->add_newarc($arc);
	}
    }
    else
    {
	debug 3, "    Same value\n";
    }

    return $arc;
}


##############################################################################

=head2 set_pred

  $a->set_pred( $pred, \%args )

Sets the pred to what we get from L<RDF::Base::Resource/get> called
from L<RDF::Base::Pred>.

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

    my $new_pred = RDF::Base::Pred->get( $pred );
    my $new_pred_id = $new_pred->id;
    my $old_pred_id = $arc->pred->id;
    my $now = now();

    $args->{'updated'} = $now;

    if( $new_pred_id != $old_pred_id )
    {
	debug "Update arc ".$arc->sysdesig.", setting pred to ".$new_pred->plain."\n" if $DEBUG;

	my $narc = RDF::Base::Arc->
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


##############################################################################

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

    my $dbix = $RDF::dbix;

    my $updated = now();
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, submitted='true' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );
    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;

    $arc->{'arc_updated_obj'} = $updated;
    $arc->{'arc_updated'} = $date_db;
    $arc->{'submitted'} = 1;

#    $arc->reset_cache; # not needed

    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;

    return 1;
}


##############################################################################

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

    my $new = RDF::Base::Arc->create({
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


##############################################################################

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

    my $dbix = $RDF::dbix;

    my $updated = now();
    my $date_db = $dbix->format_datetime($updated);

    my $st = "update arc set updated=?, submitted='false' where ver=?";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( $date_db, $arc->id );
    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;

    $arc->{'arc_updated_obj'} = $updated;
    $arc->{'arc_updated'} = $date_db;
    $arc->{'submitted'} = 0;

#    $arc->reset_cache; # not needed

    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;

    return 1;
}


##############################################################################

=head2 activate

  $a->activate( \%args )

Activates the arc.

Supported args:

  updated - time of activation
  force
  recursive - activate obj submitted arcs created by the same user


Returns: the number of changes

Exceptions: validation

=cut

sub activate
{
    my( $arc, $args_in ) = @_;
    my( $args ) = parse_propargs( $args_in );

#    debug "Activating ".$arc->sysdesig;

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
            cluck "Missed to validate arc";
	    throw('validation', "Arc $aid is not yet submitted");
	}
    }

    my $updated = $args->{'updated'} || now();
    my $activated_by = $Para::Frame::REQ->user;

    my $aarc = $arc->active_version;


    my $activated_by_id = $activated_by->id;
    my $dbix = $RDF::dbix;
    my $date_db = $dbix->format_datetime($updated);

    my $weight = $arc->weight;
    my $weight_last = $arc->{'arc_weight_last'};

    if( $arc->{'valtype'} ) # Not a REMOVAL arc
    {

#        debug "  not a removal";
	# Replaces is already set if this version is based on another
	# It may be another version than the currently active one

	my $st = "update arc set updated=?, activated=?, activated_by=?, weight=?, active='true', submitted='false' where ver=?";
	my $sth = $dbix->dbh->prepare($st);
	$sth->execute( $date_db, $date_db, $activated_by_id, $weight, $aid );
	$RDF::Base::Resource::TRANSACTION{ $aid } = $Para::Frame::REQ;

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
#        debug "  is a removal";
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
	$RDF::Base::Resource::TRANSACTION{ $aid } = $Para::Frame::REQ;

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
    $arc->notify_change( $args );

    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;

    my $obj = $arc->obj;
    if( $args->{'recursive'} and $obj )
    {
	my $created_by = $arc->created_by;
	foreach my $rarc ( $obj->arc_list(undef,undef,[['submitted','explicit']])->as_array )
	{
	    if( $rarc->created_by->equals( $created_by ) )
	    {
		debug "Recursive activation of submitted arc";
		$rarc->activate($args);
	    }
	}
    }

    if( $weight_last )
    {
        $arc->set_weight(0, {%$args,arc_weight_last=>1}); # Trigger a resort
    }

    return 1;
}


##############################################################################

=head2 reactivate

  $a->reactivate( \%args )

Tries to undo changes to the arc.

=cut

sub reactivate
{
    my( $arc, $args ) = @_;

    confess "args missing" unless $args;
    my $rargs = {%$args, force=>1};
    my $larcs = $arc->replaced_by->sorted( 'id', 'desc' );
    foreach my $larc ( $larcs->nodes )
    {
	$larc->remove($rargs);
    }

    if( $arc->old )
    {
	my $dbix = $RDF::dbix;
	my $updated = $args->{'updated'} || now();
	my $updated_db = $dbix->format_datetime($updated);
	my $aid = $arc->id;

	my $st = "update arc set updated=?, active='true', deactivated=null where ver=?";
	my $sth = $dbix->dbh->prepare($st);
	$sth->execute( $updated_db, $aid );
	$RDF::Base::Resource::TRANSACTION{ $aid } = $Para::Frame::REQ;

	$arc->{'arc_updated_obj'} = $updated_db;
	delete $arc->{'arc_deactivated_obj'};
	delete $arc->{'arc_deactivated'};
	$arc->{'active'} = 1;

	# Reset caches
	#
	$arc->obj->reset_cache if $arc->obj;
	$arc->subj->reset_cache;

	# Runs create_check AFTER deactivation of other arc version, since
	# the new arc version may INFERE the old arc
	#
	$arc->schedule_check_create( $args );
	$arc->notify_change( $args );

	debug "Reactivated ".$arc->sysdesig;
    }

    return $arc;
}



##############################################################################

=head2 set_replaces

  $a->set_replaces( $arc2, \%args )

=cut

sub set_replaces
{
    my( $arc, $arc2, $args_in ) = @_;
    my( $args ) = parse_propargs( $args_in );

    my $common_id_old = $arc->common_id;
    my $common_id     = $arc2->common_id;

    if( $RDF::Base::Cache::Resource{ $common_id } )
    {
	confess "Too late for changing arcs common_id";
    }

    if( $arc->active )
    {
	confess "Can't set replaces for active arc";
    }

    my $arc2_id = $arc2->id;

    my $dbh = $RDF::dbix->dbh;
    my $sth = $dbh->prepare("update arc set id=?, replaces=? where ver=?");
    $sth->execute($common_id, $arc2_id, $arc->id);
    $RDF::Base::Resource::TRANSACTION{ $arc->id } = $Para::Frame::REQ;

    $arc->{'common_id'} = $common_id;
    delete $arc->{'common'};
    $arc->{'replaces'} = $arc2_id;

    return $arc;
}


#########################################################################

=head1 Private methods

=cut

##############################################################################

=head2 set_explicit

  $a->set_explicit

  $a->set_explicit( $bool )

Default C<$bool> is true.

Returns: True if set to explicit

See also L</set_implicit> and L</explicit>

=cut

sub set_explicit
{
    my( $arc, $val, $args ) = @_;
    defined $val or $val = 1;
    return not $arc->set_implicit( ($val ? 0 : 1), $args );
}


##############################################################################

=head2 set_implicit

  $a->set_implicit

  $a->set_implicit( $bool )

Default C<$bool> is true.

Returns: True if set to explicit

See also L</set_explicit> and L</implicit>

=cut

sub set_implicit
{
    my( $arc, $val, $args_in ) = @_;

    my $DEBUG = 0;

    # sets to 'true' if called without arg
    defined $val or $val = 1;

    $val = $val ? 1 : 0;
    return if $val == $arc->implicit;

    my $desc_str = $val ? 'implicit' : 'explicit';
    debug "Set $desc_str for arc id $arc->{id}: ".$arc->desig."\n" if $DEBUG;

    my $dbix      = $RDF::dbix;
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
    $RDF::Base::Resource::TRANSACTION{ $arc_ver } = $Para::Frame::REQ;

    $arc->{'arc_updated_obj'} = $now;
    $arc->{'arc_updated'} = $now_db;
    $arc->{'implicit'} = $val;

    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;
    my( $args, $arclim, $res ) = parse_propargs($args_in);
    $res->changes_add;

    return $val;
}

##############################################################################

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


##############################################################################

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

    my $dbix      = $RDF::dbix;
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
    $RDF::Base::Resource::TRANSACTION{ $arc_ver } = $Para::Frame::REQ;

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

    $RDF::Base::Cache::Changes::Updated{$arc->id} ++;

    return $val;
}


##############################################################################

=head2 set_weight

  $a->set_weight( $int, \%args )

It may be set to C<undef> to unset any previous value

Setting a new weight will create a new version if the arc is active.

The arc C<arc_weight_last> will resort other arcs of the subject with
the same predicate, to put this arc last. This will only be done for
active arcs. Non-active arcs will have the property sent until the
object is gone from memory. arc_weight_last must only be used with the
weitht 0.

Supported args are:

  force_same_version
  arc_weight_last

Returns: the arc with the new weight

=cut

sub set_weight
{
    my( $arc, $val_in, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $DEBUG = 0;

    my $val = $val_in;
    if( ref $val )
    {
	$val = $val_in->plain;
    }

    my $weight_old = $arc->weight;

    if( defined $val )
    {
	unless( looks_like_number( $val ) )
	{
	    throw 'validation', "String $val is not a number";
	}

	if( $args->{arc_weight_last} and $arc->active )
	{
	    unless( $val == 0 )
	    {
                cluck "error in set_weight";
		throw 'validation', "$val must be 0 for weight last";
	    }

            $arc->weight_last( {%$args,arc_weight_last=>undef} );
        }

	# Return if no change
	return $arc if $weight_old and ($val == $weight_old);

    }
    else
    {
	return $arc unless defined $weight_old; # Return if no change
    }

    my $desc_str = defined $val ? $val : '<undef>';
    debug "Set weight $desc_str for arc id $arc->{id}: ".$arc->desig."\n" if $DEBUG;

    my $same_version = $args->{'force_same_version'} || 0;
    unless( $same_version )
    {
	if( $arc->is_new )
	{
	    $same_version = 1;
	}
    }

    unless( $same_version )
    {
	my $new = RDF::Base::Arc->create({
					  common      => $arc->common_id,
					  replaces    => $arc->id,
					  subj        => $arc->{'subj'},
					  pred        => $arc->{'pred'},
					  value       => $arc->value,
					  value_node  => $arc->value_node,
					  arc_weight  => $val,
					  arc_weight_last =>
					  $args->{arc_weight_last},
					 }, $args );
        $res->changes_add;
	return $new;
    }




    my $dbix      = $RDF::dbix;
    my $dbh       = $dbix->dbh;
    my $arc_ver   = $arc->version_id;
    my $now       = now();
    my $now_db    = $dbix->format_datetime($now);

    my $sth = $dbh->prepare("update arc set weight=?, ".
				   "updated=? ".
				   "where ver=?");
    $sth->execute($val, $now_db, $arc_ver);
    $RDF::Base::Resource::TRANSACTION{ $arc_ver } = $Para::Frame::REQ;

    $arc->{'arc_updated_obj'} = $now;
    $arc->{'arc_updated'} = $now_db;
    $arc->{'arc_weight'} = $val;
    unless( $arc->{'active'} )
    {
	$arc->{'arc_weight_last'} = $args->{arc_weight_last};
    }

    $RDF::Base::Cache::Changes::Updated{$arc_ver} ++;
    $res->changes_add;

    return $arc;
}


##############################################################################

=head2 weight_last

  $arc->weight_last( \%args )

Increases the weight of all other arcs from the same subject with the
same predicate, by 1.

Use $arc->set_weight(-1) to trigger this resort, since this method
does not touch this arc.

The method only works on active arcs.

=cut

sub weight_last
{
    my( $arc, $args ) = @_;

    debug "Resorting, ending with ".$arc->sysdesig;

    foreach my $oa ( $arc->subj->arc_list($arc->pred,undef,'active')->nodes )
    {
        next if $oa->equals($arc);
        my $weight = $oa->weight||0;
        $oa->set_weight($weight+1, $args);
    }

    return $arc;
}

##############################################################################

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
    return $RDF::Base::Cache::Resource{$id}
      || $class->new($id, @_)->first_bless()->init(@_);
}


#########################################################################

=head2 get_by_rec_and_register

  $arc->get_by_rec_and_register($rec)

The same as L<RDF::Base::Resource/get_by_rec> except that it's makes
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

    if( my $arc = $RDF::Base::Cache::Resource{$id} )
    {
#	debug "Re-Registring arc $id";

	# Calls init in case the arc init got an error the last time
	# and hasn't got fully initialized. The init method will do a
	# simple check and just return arc if it looks like it's
	# initialized.

	# Re-regestring arc with nodes
	#
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

#    debug "init arc id $id";

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
	my $sth_id = $RDF::dbix->dbh->prepare("select * from arc where ver = ?");
	$sth_id->execute($id);
	$rec = $sth_id->fetchrow_hashref;
	$sth_id->finish;

#	$Para::Frame::REQ->{RBSTAT}{'arc init exec'}
#	  += Time::HiRes::time() - $ts;
	unless( $rec )
	{
	    if( $reset ) # NOT IN DB ANYMORE!
	    {
		debug "Arc $id does not exist in DB ";
		$arc->subj->reset_cache;
		$arc->value->reset_cache(undef);
		$arc->{disregard} ++;
		delete $RDF::Base::Cache::Resource{ $id };
		return $arc;
	    }

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

	unless( $subj = $RDF::Base::Cache::Resource{ $rec->{'subj'} } )
	{
	    $subj = RDF::Base::Resource->new( $rec->{'subj'} );
	    $bless_subj = 1;
	}

#	$Para::Frame::REQ->{RBSTAT}{'arc init subj'}
#	  += Time::HiRes::time() - $ts;
    }


    croak "Not a rec: $rec" unless ref $rec eq 'HASH';

    my $pred = RDF::Base::Pred->get( $rec->{'pred'} );

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
	    my $valtype = RDF::Base::Resource->get($valtype_id)
	      or confess "Couldn't find the valtype $valtype_id ".
		"for arc $id";
#	    debug "Arc $id valtype is $valtype_id";

	    # Literals (and arcs, preds and rules) must only have one
	    # handler class. Other resources may have many handler
	    # classes. So do not lookup instance_class for enything
	    # other than literals

	    if( ref($valtype) eq 'RDF::Base::Literal::Class' )
	    {
		$value = $valtype->instance_class->get_by_arc_rec($rec,$valtype);
	    }
	    else
	    {
		$value = RDF::Base::Resource->get_by_arc_rec($rec,$valtype);
	    }
	}

#	$Para::Frame::REQ->{RBSTAT}{'arc init novalue'}
#	  += Time::HiRes::time() - $ts;
    }

#    unless( ref $value ) ### DEBUG
#    {
#	my $valtype = RDF::Base::Resource->get($valtype_id);
#	debug "  valtype is ".$valtype->sysdesig;
#	debug "  instace class is ".$valtype->instance_class;
#	confess "  bad value ".datadump($value,2);
#    }



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
    $arc->{'value'} = $value;  # can be RDF::Base::Undef
    $arc->{'value_node'} = $pred->objtype ? undef : $rec->{'obj'};
#    debug "Setting value node of arc $id to ".($rec->{obj}||'<undef>');
    $arc->{'clean'} = $rec->{'valclean'}; # TODO: remove
    $arc->{'implicit'} = $rec->{'implicit'} || 0; # default
    $arc->{'indirect'} = $rec->{'indirect'}  || 0; # default
    $arc->{'disregard'} ||= 0; ### Keep previous value
    $arc->{'in_remove_check'} = 0;
    $arc->{'explain'} = []; # See explain() method
    $arc->{'ioid'} ||= ++ $RDF::Base::ioid; # To track obj identity
    $arc->{'common_id'} = $rec->{'id'}; # Compare with $rec->{'ver'}
    $arc->{'replaces'} = $rec->{'replaces'};
    $arc->{'source'} = $rec->{'source'};
    $arc->{'arc_weight'} = $rec->{'weight'};
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
    $RDF::Base::Cache::Resource{ $id } = $arc;


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
	debug 3, "Calling first_bless for $subj->{id}";
	$subj->first_bless->init;
    }

    # The node sense of the arc should NOT be resetted. It must have
    # been initialized on object creation

    warn timediff("arc init done") if $DEBUG > 1;

#    $Para::Frame::REQ->{RBSTAT}{'arc init'}
#      += Time::HiRes::time() - $ts;

    return $arc;
}


##############################################################################

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
#    elsif(! ref $value )
#    {
#	confess "bad value ".datadump($value,2);
#    }

    if( UNIVERSAL::isa($value, "RDF::Base::Literal") )
    {
#	debug "Setting arc for ".$value->sysdesig." to ".$arc->id;
	$value->set_arc($arc);
    }
    elsif( UNIVERSAL::isa($value, "RDF::Base::Resource::Literal") )
    {
	# Always revarc initiated
    }
    elsif(not( $value->{'arc_id'} and $value->{'arc_id'}{$id} ))
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
    if( $arc->{'value_node'} )
    {
	# Not empty now, since coupled to an arc
	delete $arc->value_node->{'new'};
    }


    return $arc;
}


##############################################################################

=head2 deregister_with_nodes

  $a->deregister_with_nodes

Must only be called then the arc no longer exists.

Returns: the arc

=cut

sub deregister_with_nodes
{
    my( $arc ) = @_;

    unless( $arc->{disregard} )
    {
	confess(sprintf "Tried to deregister active arc %s", $arc->sysdesig);
    }


    my $id = $arc->{'id'};
    my $pred = $arc->pred;
    my $subj = $arc->{'subj'};
    my $pred_name = $pred->plain;
#    my $coltype = $arc->coltype || ''; # coltype may be removal

#    if( $arc->{'active'} )
#    {
#	debug "Deregister active arc $id";
#    }
#    else
#    {
#	debug "Deregister inactive arc $id";
#    }

    # Deregister the arc with the subj
    if( $subj->{'arc_id'}{$id}  )
    {
	if( $arc->{'active'} )
	{
	    if( my $alist = $subj->{'relarc'}{ $pred_name } )
	    {
#		debug sprintf "  among %d %s arcs", $#$alist, $pred_name;

		my $i=0;
		while( $i<=$#$alist )
		{
#		    debug "  $i: ".$alist->[$i]->{id};
		    if( $alist->[$i]->{id} == $arc->{id} )
		    {
#			debug "Removed $id from ".$subj->id;
#			debug sprintf "  compared %s with %s", $alist->[$i], $arc;
			splice @$alist, $i, 1;
			last;
		    }
		    $i++;
		}
	    }
	}
	else
	{
	    if( my $alist = $subj->{'relarc_inactive'}{ $pred_name } )
	    {
		my $i=0;
		while( $i<=$#$alist )
		{
		    if( $alist->[$i]->{id} eq $arc->{id} )
		    {
#			debug "Removed $id from ".$subj->id;
			splice @$alist, $i, 1;
			last;
		    }
		    $i++;
		}
	    }
	}

	delete $subj->{'arc_id'}{$id};
    }

    # Setup Value
    my $value = $arc->{'value'};

    if( UNIVERSAL::isa($value, "RDF::Base::Literal") )
    {
	$value->set_arc(undef);
    }
    elsif( UNIVERSAL::isa($value, "RDF::Base::Resource::Literal") )
    {
	my $alist = $value->{'lit_revarc_active'};
	my $i=0;
	while( $i<=$#$alist )
	{
	    if( $alist->[$i]->{id} eq $arc->{id} )
	    {
#		debug "Removed $id from ".$value->sysdesig;
		splice @$alist, $i, 1;
		last;
	    }
	    $i++;
	}

	$alist = $value->{'lit_revarc_inactive'};
	$i=0;
	while( $i<=$#$alist )
	{
	    if( $alist->[$i]->{id} eq $arc->{id} )
	    {
#		debug "Removed $id from ".$value->sysdesig;
		splice @$alist, $i, 1;
		last;
	    }
	    $i++;
	}
    }
    elsif( $value->{'arc_id'} and $value->{'arc_id'}{$id} )
    {
	if( $arc->{'active'} )
	{
	    if( my $alist = $value->{'revarc'}{ $pred_name } )
	    {
		my $i=0;
		while( $i<=$#$alist )
		{
		    if( $alist->[$i]->{id} eq $arc->{id} )
		    {
			splice @$alist, $i, 1;
#			debug "Removed $id from ".$value->sysdesig;
			last;
		    }
		    $i++;
		}
	    }
	}
	else
	{
	    if( my $alist = $value->{'revarc_inactive'}{ $pred_name } )
	    {
		my $i=0;
		while( $i<=$#$alist )
		{
		    if( $alist->[$i]->{id} eq $arc->{id} )
		    {
			splice @$alist, $i, 1;
#			debug "Removed $id from ".$value->sysdesig;
			last;
		    }
		    $i++;
		}
	    }
	}

	delete $value->{'arc_id'}{$id};
    }

    return $arc;
}


##############################################################################

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

TODO: Rewrite L</vacuum_facet>

=cut

sub disregard
{
    return $_[0]->{'disregard'};
}


##############################################################################

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

Scheduled checks of newly added/modified arcs

Returns: ---

=cut

sub schedule_check_create
{
    my( $arc, $args_in ) = @_;

    # Use solid args for activating changes here
    # active, not_disregarded
    my %args = %$args_in;
    $args{'activate_new_arcs'} = 1;
    $args{'arclim'} = RDF::Base::Arc::Lim->parse([1+128]);
    $args{unique_arcs_prio} = [1]; # active

    if( $RDF::Base::Arc::lock_check ||= 0 )
    {
	push @RDF::Base::Arc::queue_check_add, [$arc, \%args];
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

    # Use solid args for activating changes here
    # active, not_disregarded
    my %args = %$args_in;
    $args{'activate_new_arcs'} = 1;
    $args{'arclim'} = RDF::Base::Arc::Lim->parse([1+128]);
    $args{unique_arcs_prio} = [1]; # active

    if( $RDF::Base::Arc::lock_check ||= 0 )
    {
	push @RDF::Base::Arc::queue_check_remove, [$arc, \%args];
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

    while( my $params = shift @RDF::Base::Arc::queue_check_remove )
    {
	my( $arc, $args ) = @$params;
	$arc->reset_cache;
	$arc->remove_check( $args );
    }

    while( my $params = shift @RDF::Base::Arc::queue_check_add )
    {
	# These may have been rolled back. Check if they exist at all
	my( $arc, $args ) = @$params;
	my $arc_id = $arc->{'id'} or next;

	my $sth_id = $RDF::dbix->dbh->
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

    $RDF::Base::Arc::lock_check = 0;
}


###############################################################

=head2 lock

  $a->lock

Returns: ---

=cut

sub lock
{
    my $cnt = ++ $RDF::Base::Arc::lock_check;
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
    my $cnt = -- $RDF::Base::Arc::lock_check;
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

    return if $RDF::Base::Arc::lock_check_active; # Avoid recursion

    if( $cnt == 0 )
    {
        $RDF::Base::Arc::lock_check_active = 1;
        eval
        {
            while( my $params = shift @RDF::Base::Arc::queue_check_remove )
            {
                my( $arc, $args ) = @$params;
                $arc->remove_check( $args );
            }


            # Prioritize is-relations, since they will bee needed in other
            # arcs validation
            @RDF::Base::Arc::queue_check_add = sort
            {
                ($b->[0]->pred->plain eq 'is')
                  <=>
                    ($a->[0]->pred->plain eq 'is')
                } @RDF::Base::Arc::queue_check_add;

            #debug join " + ", map{ $_->[0]->pred->plain } @RDF::Base::Arc::queue_check_add;

            while( my $params = shift @RDF::Base::Arc::queue_check_add )
            {
                my( $arc, $args ) = @$params;
                $arc->create_check( $args );
            }

            # TODO: Do all the validations AFTER the create_check, since
            # the validation may need infered relations. Ie; move
            # validate_valtype from create_check to here and to the
            # corresponding place for then arc_lock isn not active.
        };
        $RDF::Base::Arc::lock_check_active = 0;
        die $@ if $@;
    }
}


###############################################################

=head2 unlock_all

  $a->unlock_all

Returns: ---

=cut

sub unlock_all
{
    $RDF::Base::Arc::lock_check ||= 0;
    $RDF::Base::Arc::lock_check = 0 if $RDF::Base::Arc::lock_check < 0;

    while( $RDF::Base::Arc::lock_check )
    {
	RDF::Base::Arc->unlock;
    }
}


###############################################################

=head2 clear_queue

  $a->clear_queue

Returns: ---

=cut

sub clear_queue
{
    @RDF::Base::Arc::queue_check = ();
    $RDF::Base::Arc::lock_check = 0;
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

    # validate_check is used for checking if this arc can be
    # infered. No reason to check that it has a valid
    # valtype. Expecially since the arc may be about to be removed and
    # in that case probably isn't valid anymore.
#    $arc->validate_valtype;

    debug( sprintf "  Retrieve list C for pred %s in %s",
	  $pred->plain, $arc->sysdesig) if $DEBUG;

    $arc->{'explain'} = []; # Reset the explain list

    if( my $list_c = RDF::Base::Rule->list_c($pred) )
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

    $arc->validate_valtype;

    if( my $list_a = RDF::Base::Rule->list_a($pred) )
    {
	foreach my $rule ( @$list_a )
	{
	    debug( sprintf  "  using %s",
		   $rule->sysdesig) if $DEBUG;

	    $rule->create_infere_rel($arc, $args);
	}
    }

    if( my $list_b = RDF::Base::Rule->list_b($pred) )
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
	# TODO: Place this in RDF::Base::Class
	$subj->on_class_perl_module_change($arc, $pred_name, $args);
    }


    $subj->on_arc_add($arc, $pred_name, $args);

    if( my $obj = $arc->obj )
    {
        $obj->on_revarc_add($arc, $pred_name, $args);
    }
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
	# TODO: Place this in RDF::Base::Class
	$subj->on_class_perl_module_change($arc, $pred_name, $args);
    }

    if( my $list_a = RDF::Base::Rule->list_a($pred) )
    {
	foreach my $rule ( @$list_a )
	{
	    $rule->remove_infered_rel($arc, $args);
	}
    }

    if( my $list_b = RDF::Base::Rule->list_b($pred) )
    {
	foreach my $rule ( @$list_b )
	{
	    $rule->remove_infered_rev($arc, $args);
	}
    }

    $subj->on_arc_del($arc, $pred_name, $args);

    if( my $obj = $arc->obj )
    {
        $obj->on_revarc_del($arc, $pred_name, $args);
    }

    $arc->{'in_remove_check'} --;
    $arc->{'disregard'} --;
    warn "Unset disregard arc $arc->{id} #$arc->{ioid} (now $arc->{'disregard'})\n" if $DEBUG;
}


###############################################################

=head2 notify_change

  $a->notify_change( \%args )

Will mark dependant nodes as updated unless for

=cut

sub notify_change
{
    my( $arc, $args ) = @_;

    my $pred_name = $arc->pred->plain;

    return if $pred_name =~ /^(un)?seen_by$/;

    if( my $obj = $arc->obj ) # obj or value node
    {
	$obj->mark_updated($args->{'updated'}) if $obj->node_rec_exist;
    }

    my $subj = $arc->subj;
    $subj->mark_updated($args->{'updated'}) if $subj->node_rec_exist;

    return;
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

    if( $val_valtype->id == $RDF::Base::Resource::ID )
    {
	# Always valid
    }
    elsif( $valtype->id == $RDF::Base::Resource::ID )
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
    if( $pred_valtype->id != $RDF::Base::Resource::ID )
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

	    ### Unfinished?
	    debug "Range check possibly failed for $subjd -${predd}-> $vald ".
	      "(should have been $pred_valtd)";
	}
    }

    return 1;
}


###############################################################

=head2 validate_valtype

  a) $a->validate_valtype( \%args )

  b) RDF::Base::Arc->validate_valtype( \%args )

The second form allows for validation of an arc before it's
creation. In that case, the args must contain C<subj>, C<pred>,
C<value> and C<valtype>. C<valtype> will default to pred range if not
given.



Returns: true or exception


=cut

sub validate_valtype
{
    my( $arc, $args ) = @_;

    # Validate arc valtype
    #
    # $valtype is given as a prop or taken from the pred valtype
    # $val_valtype is the detected valtype of the given value
    # The $val_valtype must be the same or more specific than $valtype

    # Except that the valtype for resources is inexact and will
    # usually indicate one of the classes used for blessing the
    # node. We must also check all the is-relations of the
    # object. Valtypes is mostly intended for literals.

    # Example: $valtype=$organization; $val_valtype=$hotel;
    # valid because a $hotel is a subclass of $organization

    my( $valtype, $value_obj, $pred, $subj );


    # Do not validate during startup, for bootstrapping
    #
    return 1 if $RDF::Base::IN_STARTUP;

    if( ref $arc )
    {
	$valtype = $arc->valtype;
	$value_obj = $arc->value;
	$pred = $arc->pred;
	$subj = $arc->subj;
    }
    else
    {
	$value_obj = $args->{'value'} or confess "Missing value";
	$pred = $args->{'pred'} or confess "Missing pred";
	$subj = $args->{'subj'} or confess "Missing subj";

	$valtype = $args->{'valtype'} || $pred->valtype;
    }

    if( $valtype )
    {
	if( $pred->objtype )
	{
	    # Fall back on 'resource' for Undef value_obj
	    my $res = RDF::Base::Resource->get_by_id($RDF::Base::Resource::ID);
	    my $val_valtype = $value_obj->this_valtype || $res;

	    if( $valtype->id == $RDF::Base::Resource::ID )
	    {
		# Generic, to be specified
	    }
	    elsif( not $valtype->equals( $val_valtype ) )
	    {
		if( $val_valtype->scof( $valtype ) )
		{
		    # In valid range
		}
		elsif( $value_obj->is( $valtype ) )
		{
		    # In valid range
		    $val_valtype = $valtype;
		}
		else
		{
		    my $subjd = $subj->sysdesig;
		    my $predd = $pred->plain;
		    my $val_valtd = $val_valtype->sysdesig;
		    my $valtd = $valtype->sysdesig;
		    my $vald = $value_obj->sysdesig;
		    my $err = "Valtype validation failed for\n";
		    $err .= "  $subjd --${predd}--> $vald\n";
		    $err .= "  The expected valtype for the arc is $valtd\n";
		    $err .= "  The valtype of $vald was found out to be $val_valtd\n";
		    if( $val_valtype->id == $RDF::Base::Resource::ID )
		    {
			$err .= "  Put $vald in the class $valtd\n";
		    }
		    else
		    {
			$err .= "  $val_valtd must be a subclass of $valtd\n";
		    }
		    $err .= "  (do you need to use arc_lock?)\n";

		    throw('validation',$err, \ longmess);
#		    confess $err;
		}
	    }
	}
	else
	{
	    # Example of situation:

#Valtype validation failed for
# 6904167: 43ZAFV --due--> Date 2008-10-13 08.35.19 +0200
# The expected valtype for the arc is 1213710: date
# The valtype of Date 2008-10-13 08.35.19 +0200 was found out to be 1213707: valdate
# 1213707: valdate must be a subclass of 1213710: date



#	    my $val_valtype = $value_obj->this_valtype;
#
#
#	    if( not $valtype->equals( $val_valtype ) )
#	    {
#		if( $val_valtype->scof( $valtype ) )
#		{
#		    # In valid range
#		}
#		elsif( $value_obj->is( $valtype ) )
#		{
#		    # In valid range
#		    $val_valtype = $valtype;
#		}
#		else
#		{
#		    my $subjd = $arc->subj->sysdesig;
#		    my $predd = $pred->plain;
#		    my $val_valtd = $val_valtype->sysdesig;
#		    my $valtd = $valtype->sysdesig;
#		    my $vald = $value_obj->sysdesig;
#		    my $err = "Valtype validation failed for\n";
#		    $err .= "  $subjd --${predd}--> $vald\n";
#		    $err .= "  The expected valtype for the arc is $valtd\n";
#		    $err .= "  The valtype of $vald was found out to be $val_valtd\n";
#		    $err .= "  $val_valtd must be a subclass of $valtd\n";
#		    confess $err;
#		}
#	    }
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

	my $req = $Para::Frame::REQ;
	
    return '' unless $req->user->has_root_access;
	  
	return '' unless $req->session->{'advanced_mode'};
	  

    my $home   = $req->site->home_url_path;
    my $arc_id = $arc->id;
    my $a_id   = "edit_arc_link_$arc_id";

    return
      (
       "<a id=\"$a_id\" href=\"$home/rb/node/arc/update.tt?"
       . "id=$arc_id\" class=\"edit_arc_link\"><i class=\"fa fa-pencil-square-o\"></i></a>"
       . "<script type=\"text/javascript\">\n"
       . "  \$('#$a_id').tipsy("
       . to_json({
                  fallback => $arc->info_updated_html($args),
                  html     => 'true',
#                  live     => 'true',
                  delayOut => 2000,
                 })
       . "  );"
       . "</script>"
      );
    # TODO: Fix a method to add late-loaded scriptfragments, added
    # just before </body>, preferrably minified in ONE <script>, not a
    # hundred :P
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
	return RDF::Base::Resource->get_by_label('rdfbase');
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
	return RDF::Base::Resource->get_by_label('public');
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
	return RDF::Base::Resource->get_by_label('sysadmin_group');
    }
}


###############################################################

=head2 use_class

=cut

sub use_class
{
    return "RDF::Base::Arc";
}


###############################################################

=head2 list_class

=cut

sub list_class
{
    return "RDF::Base::Arc::List";
}


###################################################################

=head2 as_rdf

=cut

sub as_rdf
{
    my( $a ) = shift;

    my $out = "";
    my $predl = $a->pred->label;
    my $val = $a->value;
    if( $val->is_literal )
    {
        my $type = $val->this_valtype;
        my $val_out = CGI->escapeHTML($val);
        my $type_label = $type->label || $type->id;
        $out .= qq(<rb:$predl rdf:datatype="$type_label">$val_out</rb:$predl>\n);
    }
    else
    {
        my $res_out = $val->label || $val->id;
        $out .= qq(<rb:$predl rdf:resource="$res_out"/>\n);
    }

    return $out;
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
    my $ts = $RDF::Base::timestamp;
    $RDF::Base::timestamp = time;
    return sprintf "%20s: %2.3f\n", $_[0], time - $ts;
}


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource>,
L<RDF::Base::Pred>,
L<RDF::Base::List>,
L<RDF::Base::Search>

=cut
