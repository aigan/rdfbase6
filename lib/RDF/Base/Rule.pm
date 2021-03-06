package RDF::Base::Rule;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Rule

=cut

use 5.014;
use warnings;
use base qw( RDF::Base::Resource );
use vars qw( $INITIALIZED );

use Carp qw( cluck confess );
use List::Uniq qw( uniq );

use Para::Frame;
use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use RDF::Base::Utils qw( is_undef parse_propargs );
use RDF::Base::Constants qw( $C_syllogism $C_is );


our( %Rules, %List_A, %List_B, %List_C );


=head1 DESCRIPTION

Represents a inference rule.

Inherits from L<RDF::Base::Resource>.

=cut



#########################################################################
################################ Initialize package #####################

=head2 on_configure

=cut

sub on_configure
{
#    cluck "  ----------> Initializing \%Rules\n";

    %Rules = ();

    my $rules = $C_syllogism->revlist($C_is);

    foreach my $rule ( $rules->as_array )
    {
        $Rules{$rule->id} = $rule;
    }

    RDF::Base::Rule->build_lists();

    $INITIALIZED = 1;           # Class flag

    return 1;
}

=head2 build_lists

=cut

sub build_lists
{
    %List_A = ();
    %List_B = ();
    %List_C = ();

    foreach my $rule ( values %Rules )
    {
        push @{$List_A{ $rule->a->id }}, $rule;
        push @{$List_B{ $rule->b->id }}, $rule;
        push @{$List_C{ $rule->c->id }}, $rule;
    }
}


##############################################################################

=head2 init

=cut

sub init
{
    my( $rule ) = @_;

    debug 2, "Initiated rule $rule->{id}";

    $rule->{'a'} = $rule->first_prop('pred_1');
    $rule->{'b'} = $rule->first_prop('pred_2');
    $rule->{'c'} = $rule->first_prop('pred_3');

    return $rule;
}


##############################################################################

=head2 on_bless

=cut

sub on_bless
{
    return $_[0]->init;
}


##############################################################################

=head2 on_unbless

=cut

sub on_unbless
{
    my( $rule, $class, $args_in ) = @_;

    debug "Removing rule ".$rule->sysdesig;

    my $id = $rule->id;
    my $pred;


    foreach my $key (keys %List_A)
    {
        my @newlist;
        foreach my $rule ( @{$List_A{$key}} )
        {
            if ( $rule->id eq $id )
            {
                debug "Skipping rule $id in A";
                next;
            }
            push @newlist, $rule;
        }

        $List_A{$key} = \@newlist;
    }

    foreach my $key (keys %List_B)
    {
        my @newlist;
        foreach my $rule ( @{$List_B{$key}} )
        {
            if ( $rule->id eq $id )
            {
                debug "Skipping rule $id in B";
                next;
            }
            push @newlist, $rule;
        }

        $List_B{$key} = \@newlist;
    }

    foreach my $key (keys %List_C)
    {
        my @newlist;
        foreach my $rule ( @{$List_C{$key}} )
        {
            if ( $rule->id eq $id )
            {
                $pred = RDF::Base::Resource->get($key);
                debug "Skipping rule $id in C";
                next;
            }
            push @newlist, $rule;
        }

        $List_C{$key} = \@newlist;
    }

    delete $Rules{$id};
    my $req = $Para::Frame::REQ;

    if ( $pred )
    {
        my $arcs = $pred->active_arcs;
        $req->note(sprintf "Vacuuming %d arcs", $arcs->size);
        my( $arc, $error ) = $arcs->get_first;
        while (! $error )
        {
            next unless $arc->objtype;
            next unless $arc->active;

            unless( $arc->validate_check )
            {
                next if $arc->explicit;
                $arc->remove($args_in);
            }
        }
        continue
        {
            unless( $arcs->count % 1000 )
            {
                $req->note( sprintf "Vacuumed arc %6d of %6d",
                            $arcs->count, $arcs->size );
                $req->may_yield;
            }
            ( $arc, $error ) = $arcs->get_next;
        }
    }
}


###############################################################

=head2 use_class

=cut

sub use_class
{
    return "RDF::Base::Rule";
}


###############################################################

=head2 this_valtype

=cut

sub this_valtype
{
    return $C_syllogism;
}


#########################################################################
################################  Constructors  #########################

=head1 Constructors

=cut

##############################################################################

=head2 create

  $class->create( $a, $b, $c, $vacuum)

Create a new rule.  Implement the rule in the DB.

Does nothing if the rule already exists.

=cut

sub create
{
    my( $this, $a, $b, $c, $vacuum ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('solid');
    $args->{'activate_new_arcs'} = 1;

    $INITIALIZED or $this->on_configure;

    $vacuum = 1 unless defined $vacuum;

    $a = RDF::Base::Pred->get( $a ) unless ref $a;
    $b = RDF::Base::Pred->get( $b ) unless ref $b;
    $c = RDF::Base::Pred->get( $c ) unless ref $c;


    unless( $a and $b and $c )
    {
        throw('action', "Invalid parameters to Rule add");
    }

    my $props =
    {
     pred_1 => $a,
     pred_2 => $b,
     pred_3 => $c,
     is => $C_syllogism,
    };


    my $existing_list = RDF::Base::Resource->find($props);
    if ( $existing_list->size )
    {
        my $rule = $existing_list->get_first;
        debug sprintf "%s already exist\n", $rule->sysdesig;
        return $rule;
    }

    my $rule = RDF::Base::Resource->create($props, $args);
    $rule->rebless;
    $Rules{$rule->id} = $rule;

    $this->build_lists;

    debug sprintf "Created %s\n", $rule->sysdesig;

    if ( $vacuum )
    {
        $rule->vacuum_node;
    }

    return $rule;
}



#########################################################################
################################  List constructors #####################

=head1 List constructors

=cut

##############################################################################

=head2 list_a

Returns an array ref

=cut

sub list_a
{
    my( $this, $pred ) = @_;
    $INITIALIZED or $this->on_configure;
    return $List_A{$pred->id};
}


#########################################################################

=head2 list_b

Returns an array ref

=cut

sub list_b
{
    my( $this, $pred ) = @_;
    $INITIALIZED or $this->on_configure;
    return $List_B{$pred->id};
}


#########################################################################

=head2 list_c

Returns an array ref

=cut

sub list_c
{
    my( $this, $pred ) = @_;
    $INITIALIZED or $this->on_configure;
    return $List_C{$pred->id};
}


#########################################################################
################################  Accessors  ############################

=head2 Accessors

=cut

##############################################################################

=head2 a

Get pred obj A.

=cut

sub a {shift->{'a'}}


##############################################################################

=head2 b

Get pred obj B.

=cut

sub b {shift->{'b'}}


##############################################################################

=head2 c

Get pred obj C.

=cut

sub c {shift->{'c'}}


##############################################################################

=head2 desig

  $n->desig()

The designation of the rule, to be used for node administration or
debugging.

=cut

sub desig
{
    my( $rule ) = @_;

    return sprintf( "( A %s B ) and ( B %s C ) ==> ( A %s C )",
                    $rule->a->plain,
                    $rule->b->plain,
                    $rule->c->plain,
                  );
}


##############################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of the rule, to be used for node administration or
debugging.  This version of desig indludes the node id.

=cut

sub sysdesig
{
    my( $rule ) = @_;

    return sprintf "Rule %d: %s", $rule->{'id'}, $rule->desig;
}


##############################################################################

=head2 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("rule:%d", shift->{'id'});
}


##############################################################################

=head2 loc

The translation of the rule

=cut

sub loc($)
{
    die "not defined";
}


##############################################################################

=head2 plain

Make it a plain value.  Ie, just return self...

=cut

sub plain
{
    return $_[0];
}


#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

##############################################################################

=head2 equals

=cut

sub equals
{
    my( $rule, $val ) = @_;

    if ( UNIVERSAL::isa($val,'RDF::Base::Rule') )
    {
        if ( $rule->{'id'} eq $val->{'id'} )
        {
            return 1;
        }
    }

    return 0;
}


##############################################################################

=head2 validate_infere

A full vacuum sweep of the DB will run validate and then create_check
for each arc.  In order to catch tied circular dependencies we will in
validation check validate dependencies til we found a base in explicit
arcs.

See L<RDF::Base::Arc/explain> for the explain format.

=cut

sub validate_infere
{
    my( $rule, $arc ) = @_;
    #
    # A3B & A1C & C2D & D=B
    # A1B & B2C -> A3C
    # > 1 2 3

    my $DEBUG = 0;

    debug( sprintf  "validate_infere of %s using %s",
           $arc->sysdesig, $rule->sysdesig) if $DEBUG;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->arc_list($rule->a) })
    {
        debug( sprintf  "  Check %s", $arc2->sysdesig) if $DEBUG;

        next if disregard $arc2;
        next if $arc2->id == $arc->id;

        foreach my $arc3 (@{ $arc2->obj->arc_list($rule->b) })
        {
            debug( sprintf  "    Check %s", $arc3->sysdesig) if $DEBUG;

            next if disregard $arc3;

            if ( $arc3->obj->id == $obj->id )
            {
                unless( $arc3->objtype ) # Value node
                {
                    next unless $arc3->value->equals($arc->value);
                }

                debug( "      Match!") if $DEBUG;

                my $exp =
                {
                 a => $arc2,
                 b => $arc3,
                 c => $arc,
                 rule => $rule,
                };
                # $arc->{explain} are resetted in $arc->validate_check
                push @{$arc->{'explain'}}, $exp;
                return 1;
            }
        }
    }

    debug( "  No match") if $DEBUG;
    return 0;
}


##############################################################################

=head2 create_infere_rev

Make inference on the B part on create

args res must be defined

=cut

sub create_infere_rev
{
    my( $rule, $arc, $args ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    my $DEBUG = 0;

    foreach my $arc2 (@{ $subj->revarc_list($rule->a) })
    {
        debug( sprintf  "  Check %s", $arc2->sysdesig) if $DEBUG;

        next if disregard $arc2;

        my $pred = $rule->c;
        my $subj3 = $arc2->subj;
        my $arc3_list = $subj3->arc_list($pred, $obj);

        if ( $arc3_list->size < 1 )
        {
            debug "    Less than 1" if $DEBUG;
            RDF::Base::Arc->create({
                                    subj => $subj3,
                                    pred => $pred,
                                    value => $obj,
                                    implicit => 1,
                                   },
                                   {
                                    %$args,
                                    activate_new_arcs => 1, # Activate directly
                                   });
        }
        elsif ( $arc3_list->size > 1 ) # cleanup
        {
            debug "    More than 1" if $DEBUG;
            # prioritize on explict, indirect, other
            my $choice = $arc3_list->explicit->indirect->get_first_nos
              || $arc3_list->indirect->get_first_nos
                || $arc3_list->get_first_nos;

            my( $arc3, $err ) = $arc3_list->get_first;
            while (!$err)
            {
                next if $arc3->equals($choice);
                $arc3->remove({%$args, force=>1});
            }
            continue
            {
                ( $arc3, $err ) = $arc3_list->get_next;
            }
            ;

            $choice->set_indirect;
        }
        else
        {
            debug "    Just 1" if $DEBUG;
            $arc3_list->get_first_nos->set_indirect;
        }


#	RDF::Base::Arc->find_set({
#				  pred => $rule->c,
#				  subj => $arc2->subj,
#				  obj  => $obj,
#				 },
#				 {
#				  default_create =>
#				  {
#				   implicit => 1,
#				   active => 1, # Activate directly
#				  },
#				  res => $args->{'res'},
#				 })->set_indirect;
    }
}


##############################################################################

=head2 create_infere_rel

Make inference on the A part on create

args res must be defined

=cut

sub create_infere_rel
{
    my( $rule, $arc, $args ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    my $DEBUG = 0;

    foreach my $arc2 (@{ $obj->arc_list($rule->b) })
    {
        debug( sprintf  "  Check %s", $arc2->sysdesig) if $DEBUG;

        next if disregard $arc2;

        my $pred = $rule->c;
        my $obj3 = $arc2->obj;
        my $arc3_list = $subj->arc_list($pred, $obj3);

        if ( $arc3_list->size < 1 )
        {
            debug "    Less than 1" if $DEBUG;
            RDF::Base::Arc->create({
                                    subj => $subj,
                                    pred => $pred,
                                    value => $obj3,
                                    implicit => 1,
                                   },
                                   {
                                    %$args,
                                    activate_new_arcs => 1, # Activate directly
                                   });
        }
        elsif ( $arc3_list->size > 1 ) # cleanup
        {
            debug "    More than 1" if $DEBUG;
            # prioritize on explict, indirect, other
            my $choice = $arc3_list->explicit->indirect->get_first_nos
              || $arc3_list->indirect->get_first_nos
                || $arc3_list->get_first_nos;

            my( $arc3, $err ) = $arc3_list->get_first;
            while (!$err)
            {
                next if $arc3->equals($choice);
                $arc3->remove({%$args, force=>1});
            }
            continue
            {
                ( $arc3, $err ) = $arc3_list->get_next;
            }
            ;

            $choice->set_indirect;
        }
        else
        {
            debug "    Just 1" if $DEBUG;
            $arc3_list->get_first_nos->set_indirect;
        }


#	RDF::Base::Arc->find_set({
#				  pred => $rule->c,
#				  subj => $subj,
#				  obj  => $arc2->obj,
#				 },
#				 {
#				  default_create =>
#				  {
#				   implicit => 1,
#				   active => 1, # Activate directly
#				  },
#				  res => $args->{'res'},
#				 })->set_indirect;
    }
}


##############################################################################

=head2 remove_infered_rev

Remove implicit arcs infered from this arc, part B

args res must be defined

=cut

sub remove_infered_rev
{
    my( $rule, $arc, $args ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->revarc_list($rule->a) })
    {
#	next if disregard $arc2; # not
        RDF::Base::Arc->find_remove({
                                     subj => $arc2->subj,
                                     pred => $rule->c,
                                     obj  => $obj,
                                    },
                                    {
                                     implicit => 1,
                                     res => $args->{'res'},
                                    });
    }

}


##############################################################################

=head2 remove_infered_rel

Remove implicit arcs infered from this arc, part A

args res must be defined

=cut

sub remove_infered_rel
{
    my( $rule, $arc, $args ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $obj->arc_list($rule->b) })
    {
#	next if disregard $arc2; # not
        RDF::Base::Arc->find_remove({
                                     subj => $subj,
                                     pred => $rule->c,
                                     obj  => $arc2->obj,
                                    },
                                    {
                                     implicit => 1,
                                     res => $args->{'res'},
                                    });
    }

}


##############################################################################

=head2 vacuum_facet

=cut

sub vacuum_facet
{
    my( $rule, $args_in ) = @_;

    foreach my $pred ( uniq sort
                       $rule->first_prop('pred_1'),
                       $rule->first_prop('pred_2'),
                       $rule->first_prop('pred_3'),
                     )
    {
        $pred->vacuum_pred_arcs;
    }

    return $rule;
}


########################################################################
################################  Private methods  ######################



1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
