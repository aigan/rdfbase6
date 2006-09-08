#  $Id$  -*-cperl-*-
package Rit::Base::Rule;

=head1 NAME

Rit::Base::Rule

=cut

use Carp qw( cluck confess );
use Data::Dumper;
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

sub on_configure
{
    my $dbix = $Rit::dbix;

#    warn "  ----------> Initializing \%Rules\n";

    %Rules = ();

    my $recs = $dbix->select_list("from syllogism");
    foreach my $rec ( @$recs )
    {
	my $id = $rec->{'id'};

	# Get from or store in CACHE
	#
	$Rules{$id} = $Rit::Base::Cache::Resource{$id}
	  ||= Rit::Base::Rule->get_by_rec( $rec );
#	debug "Caching node $id: $Rules{$id}";
    }

    Rit::Base::Rule->build_lists();

    $INITIALIZED = 1; # Class flag

    return 1;
}

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

    unless( $rec )
    {
	my $id = $rule->{'id'};
	my $sth_id = $Rit::dbix->dbh->prepare("select * from syllogism where id=?");
	$sth_id->execute($id);
	$rec = $sth_id->fetchrow_hashref;
	$sth_id->finish;
	$rec or confess "Rule '$id' not found";
    }

    my $a = Rit::Base::Pred->get( $rec->{'a'} );
    my $b = Rit::Base::Pred->get( $rec->{'b'} );
    my $c = Rit::Base::Pred->get( $rec->{'c'} );

    $rule->{'a'} = Rit::Base::Pred->get( $rec->{'a'} );
    $rule->{'b'} = Rit::Base::Pred->get( $rec->{'b'} );
    $rule->{'c'} = Rit::Base::Pred->get( $rec->{'c'} );

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


    my $dbix = $Rit::dbix;
    my $dbh = $dbix->dbh;

    if( my $rec = $dbix->select_possible_record("from syllogism where a=? and b=? and c=?",
						$a->id, $b->id, $c->id) )
    {
	my $id = $rec->{'id'};
	my $rule = $Rules{$id} = $Rit::Base::Cache::Resource{$id}
	  = $this->get_by_rec( $rec );
#	debug "Caching node $id: $Rules{$id}";
	debug sprintf "%s already exist\n", $rule->sysdesig;
	return $rule;
    }

    my $rec =
    {
     id => $dbix->get_nextval('node_seq'),
     a  => $a->id,
     b  => $b->id,
     c  => $c->id,
    };

    $dbh->do("insert into syllogism (id, a, b, c) values (?,?,?,?)", {},
	     $rec->{id},
	     $rec->{a},
	     $rec->{b},
	     $rec->{c},
	    );

    my $id = $rec->{'id'};
    my $rule = $Rules{$id} = $Rit::Base::Cache::Resource{$id}
      = $this->get_by_rec( $rec );
#    debug "Caching node $id: $Rules{$id}";
    $this->build_lists;
    debug sprintf "Created %s\n", $rule->sysdesig;

    # TODO: Make this a constant
    my $syllogism_class = $Rit::Base::Resource->get({
						     name => 'syllogism',
						     scof => 'rule',
						    });
    $rule->add({ is => $syllogism_class });

    if( $vacuum )
    {
	use Array::Uniq;
	foreach my $pred_id ( uniq sort @{$rec}{'a','b','c'} )
	{
	    # TODO: create_check for rels instead
	    my $sth = $dbh->prepare( "select * from rel where pred=?" );
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

=head2 id

Get rule id.

=cut

sub id
{
    my( $rule ) = @_;

    ref $rule or confess "Not an object: $rule";

    return $rule->{'id'};
}


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

    if( ref $val eq 'Rit::Base::Rule' )
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
	$arc2->find_set({
			 pred => $rule->c,
			 subj => $arc2->subj,
			 obj  => $obj,
			 implicit => 1,
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
	$arc2->find_set({
			 pred => $rule->c,
			 subj => $subj,
			 obj  => $arc2->obj,
			 implicit => 1,
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
	$arc2->find_remove({
			    subj => $arc2->subj,
			    pred => $rule->c,
			    obj  => $obj,
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
	$arc2->find_remove({
			    subj => $subj,
			    pred => $rule->c,
			    obj  => $arc2->obj,
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
