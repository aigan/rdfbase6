#  $Id$  -*-cperl-*-
package Rit::Base::Rule;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource Rule class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Rule

=cut

use Carp qw( cluck confess );
use strict;
use vars qw( $INITIALIZED );


BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame;
use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base::Utils qw( is_undef );
use Rit::Base::Constants qw( $C_syllogism );


### Inherit
#
use base qw( Rit::Base::Resource );

our( %Rules, %List_A, %List_B, %List_C );


=head1 DESCRIPTION

Represents a inference rule.

Inherits from L<Rit::Base::Resource>.

=cut



#########################################################################
################################ Initialize package #####################

=head2 on_configure

=cut

sub on_configure
{
    warn "  ----------> Initializing \%Rules\n";

    %Rules = ();

    my $rules = $C_syllogism->revlist('is');

    foreach my $rule ( $rules->as_array )
    {
	$Rules{$rule->id} = $rule;
    }

    Rit::Base::Rule->build_lists();

    $INITIALIZED = 1; # Class flag

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


#########################################################################
################################  Constructors  #########################

=head1 Constructors

=cut

#######################################################################

=head2 init

=cut

sub init
{
    my( $rule, $rec ) = @_;

    $rule->{'a'} = $rule->first_prop('pred_1');
    $rule->{'b'} = $rule->first_prop('pred_2');
    $rule->{'c'} = $rule->first_prop('pred_3');

    return $rule;
}


#######################################################################

=head2 create

Create a new rule.  Implement the rule in the DB.

Does nothing if the rule already exists.

=cut

sub create
{
    my( $this, $a, $b, $c, $vacuum ) = @_;

    $INITIALIZED or $this->on_configure;

    $vacuum = 1 unless defined $vacuum;

    $a = Rit::Base::Pred->get( $a ) unless ref $a;
    $b = Rit::Base::Pred->get( $b ) unless ref $b;
    $c = Rit::Base::Pred->get( $c ) unless ref $c;


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


    my $existing_list = Rit::Base::Resource->find($props);
    if( $existing_list->size )
    {
	my $rule = $existing_list->get_first;
	debug sprintf "%s already exist\n", $rule->sysdesig;
	return $rule;
    }

    my $rule = Rit::Base::Resource->create($props);
    $Rules{$rule->id} = $rule;

    $this->build_lists;

    debug sprintf "Created %s\n", $rule->sysdesig;

    if( $vacuum )
    {
	use Array::Uniq;
	my $dbh = $Rit::dbix->dbh;
	my $sth = $dbh->prepare( "select * from arc where pred=?" );
	foreach my $pred_id ( uniq sort $a->id, $b->id, $c->id )
	{
	    # TODO: create_check for rels instead
	    $sth->execute( $pred_id );
	    while( my( $rec ) = $sth->fetchrow_hashref )
	    {
		Rit::Base::Arc->get_by_rec( $rec )->vacuum;
	    }
	    $sth->finish;
	}
    }

    return $rule;
}



#########################################################################
################################  List constructors #####################

=head1 List constructors

=cut

#######################################################################

=head2 find

List all rules. Returns a Rit::Base::List object

=cut

sub find
{
    my( $this ) = @_;
    $INITIALIZED or $this->on_configure;
    my $rules_listref =  [ values %Rules ];
    return Rit::Base::List->new($rules_listref);
}


#######################################################################

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

#######################################################################

=head2 a

Get pred obj A.

=cut

sub a {shift->{'a'}}


#######################################################################

=head2 b

Get pred obj B.

=cut

sub b {shift->{'b'}}


#######################################################################

=head2 c

Get pred obj C.

=cut

sub c {shift->{'c'}}


#######################################################################

=head2 desig

  $n->desig()

The designation of the rule, to be used for node administration or
debugging.

=cut

sub desig
{
    my( $rule ) = @_;

    return sprintf( "( A %s B ) and ( B %s C ) ==> ( A %s C )",
		    $rule->a->name->plain,
		    $rule->b->name->plain,
		    $rule->c->name->plain,
		  );
}


#######################################################################

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


#######################################################################

=head2 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("rule:%d", shift->{'id'});
}


#######################################################################

=head2 loc

The translation of the rule

=cut

sub loc($)
{
    die "not defined";
}


#######################################################################

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

#######################################################################

=head2 equals

=cut

sub equals
{
    my( $rule, $val ) = @_;

    if( UNIVERSAL::isa($val,'Rit::Base::Rule') )
    {
	if( $rule->{'id'} eq $val->{'id'} )
	{
	    return 1;
	}
    }

    return 0;
}


#######################################################################

=head2 validate_infere

A full vacuum sweep of the DB will run validate and then create_check
for each arc.  In order to catch tied circular dependencies we will in
validation check validate dependencies til we found a base in explicit
arcs.

See L<Rit::Base::Arc/explain> for the explain format.

=cut

sub validate_infere
{
    my( $rule, $arc ) = @_;
    #
    # A3B & A1C & C2D & D=B
    # A1B & B2C -> A3C
    # > 1 2 3

    my $DEBUG = 0;

    debug( sprintf  "validate_infere of %s using %s\n",
	  $arc->sysdesig, $rule->sysdesig) if $DEBUG;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->arc_list($rule->a) })
    {
	debug( sprintf  "  Check %s\n", $arc2->sysdesig) if $DEBUG;

	next if disregard $arc2;
	next if $arc2->id == $arc->id;

	foreach my $arc3 (@{ $arc2->obj->arc_list($rule->b) })
	{
	    debug( sprintf  "    Check %s\n", $arc3->sysdesig) if $DEBUG;

	    next if disregard $arc3;

	    if( $arc3->obj->id == $obj->id )
	    {
		debug( "      Match!\n") if $DEBUG;

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

    debug( "  No match\n") if $DEBUG;
    return 0;
}


#######################################################################

=head2 create_infere_rev

Make inference on the B part on create

=cut

sub create_infere_rev
{
    my( $rule, $arc ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->revarc_list($rule->a) })
    {
	next if disregard $arc2;
	Rit::Base::Arc->find_set({
				  pred => $rule->c,
				  subj => $arc2->subj,
				  obj  => $obj,
				 },
				 {
				  default_create =>
				  {
				   implicit => 1,
				   active => 1, # Activate directly
				  },
				 })->set_indirect;
    }
}


#######################################################################

=head2 create_infere_rel

Make inference on the A part on create

=cut

sub create_infere_rel
{
    my( $rule, $arc ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $obj->arc_list($rule->b) })
    {
	next if disregard $arc2;
	Rit::Base::Arc->find_set({
				  pred => $rule->c,
				  subj => $subj,
				  obj  => $arc2->obj,
				 },
				 {
				  default_create =>
				  {
				   implicit => 1,
				   active => 1, # Activate directly
				  },
				 })->set_indirect;
    }
}


#######################################################################

=head2 remove_infered_rev

Remove implicit arcs infered from this arc, part B

=cut

sub remove_infered_rev
{
    my( $rule, $arc ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $subj->revarc_list($rule->a) })
    {
#	next if disregard $arc2; # not
	Rit::Base::Arc->find_remove({
				     subj => $arc2->subj,
				     pred => $rule->c,
				     obj  => $obj,
				    },
				    {
				     implicit => 1,
				    });
    }

}


#######################################################################

=head2 remove_infered_rel

Remove implicit arcs infered from this arc, part A

=cut

sub remove_infered_rel
{
    my( $rule, $arc ) = @_;

    # Check subj and obj
    my $subj = $arc->subj;
    my $obj  = $arc->obj;
    return 0 unless $obj;

    foreach my $arc2 (@{ $obj->arc_list($rule->b) })
    {
#	next if disregard $arc2; # not
	Rit::Base::Arc->find_remove({
				     subj => $subj,
				     pred => $rule->c,
				     obj  => $arc2->obj,
				    },
				    {
				     implicit => 1,
				    });
    }

}


########################################################################
################################  Private methods  ######################



1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
