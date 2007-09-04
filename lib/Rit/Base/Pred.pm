#  $Id$  -*-cperl-*-
package Rit::Base::Pred;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource Pred class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Pred

=cut

use Carp qw( cluck confess carp croak );
use strict;
use Time::HiRes qw( time );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Reload;

use Rit::Base::List;
use Rit::Base::Utils qw( valclean translate is_undef );
use Rit::Base::Literal::String;


### Inherit
#
use base qw( Rit::Base::Resource );


#### INIT

our $special_id =
{
 id     => -1,
 score  => -2,
 random => -3,
 desig  => -4,
 'loc'   => -5,
 plain  => -6,
 subj => -7,
 pred => -8,
 obj => -9,
 coltype => -10,
};

our $special_label = { reverse %$special_id };

=head1 DESCRIPTION

Represents preds.

Inherits from L<Rit::Base::Resource>.

=cut




#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

#######################################################################

=head2 id

  $p->id

An id of the node, not conflicting with any other
L<Rit::Base::Resource>.

Returns: An integer

=cut

sub id
{
    my( $pred ) = @_;

    return $pred->{'id'};
}

#######################################################################

=head2 name

  $p->name

Returns: The name of the predicate as a L<Rit::Base::Literal::String> object

=cut

sub name
{
    my( $pred ) = @_;

    confess "not an obj: $pred" unless ref $pred;
    return new Rit::Base::Literal::String $pred->{'label'};
}

#######################################################################

=head2 value

Same as L</name>

=cut

sub value
{
    $_[0]->name;
}

#######################################################################

=head2 plain

  $p->plain

Same as C<$p->name->plain>

Returns: The name as a scalar string

=cut

sub plain
{
    $_[0]->{'label'};
}

#######################################################################

=head2 syskey

  $p->syskey

Returns a unique predictable id representing this object, as a scalar
string

=cut

sub syskey
{
    return sprintf("pred:%d", shift->{'id'});
}


#######################################################################

=head2 valtype

  $p->valtype()

Find the valtype of a predicate.  This will use the range or the coltype.

Returns: A C<valtype> node to use as the valtype for arcs with this pred.

Exceptions: Will confess if trying to get a valtype from the value pred.

=cut

sub valtype
{
    my( $pred ) = @_;

    if( my $range = $pred->first_prop('range') )
    {
	return $range;
    }
    else
    {
	if( $pred->{'coltype'} == 6 )
	{
	    confess "Predicate 'value' has no valtype";
	}

	my $coltype = Rit::Base::Literal::Class->
	  coltype_by_coltype_id( $pred->{'coltype'} );
	if( $coltype eq 'obj' )
	{
	    return Rit::Base::Constants->get('resource');
	}
	else
	{
	    return Rit::Base::Constants->get( $coltype );
	}
    }
}

#######################################################################

=head2 objtype

  $p->objtype()

Returns true if the L</coltype> the value is 'obj'.  This will not
return true if the real value is a literal resource, unless the
literal resource has a value that is a node.

Calls L</coltype>.

Returns: 1 or 0

=cut

sub objtype
{
    return shift->coltype eq 'obj' ? 1 : 0;
}


#######################################################################

=head2 coltype

  $p->coltype()

The retuned value will be one of C<obj>, C<valtext>,
C<valdate>, C<valfloat> or C<valbin>.

Returns: A scalar string

=cut

sub coltype
{
    unless( $_[0]->{'coltype'} )
    {
	confess "Pred ".$_[0]->sysdesig." is missing a coltype";
    }

    return Rit::Base::Literal::Class->
      coltype_by_coltype_id( $_[0]->{'coltype'} );
}

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

#######################################################################

=head2 is_pred

Is this a pred? Yes.

Returns: 1

=cut

sub is_pred { 1 };


#########################################################################
################################  Private methods  ######################

=head2 find_by_anything

  $this->find_by_anything( $label, \%args )

Supported args are:

  return_single_value

=cut

sub find_by_anything
{
    my( $this, $label, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $no_list = $args->{'return_single_value'} || 0;

#    warn "New pred $label\n"; ### DEBUG

    if( ref $label )
    {
	if( UNIVERSAL::isa( $label, 'Rit::Base::Literal') )
	{
	    $label = $label->literal;
	}
	elsif( UNIVERSAL::isa( $label, 'Rit::Base::Pred') )
	{
	    return $label;
	}
	else
	{
	    if( UNIVERSAL::isa( $label, 'Rit::Base::Resource') )
	    {
		confess "Pred not a pred: ".$label->sysdesig;
	    }
	    confess "Pred label format $label not supported";
	}
    }

    $label = $label->literal if ref $label;
    $label or confess "get_by_anything got empty label";


    # TODO: Insert special predicates subj, pred, obj, coltype

    # Special properties
    if( $label =~ /^(id|score|random)$/ )
    {
	return $class->get_by_node_rec({
					label   => $1,
					node    => $special_id->{$1},
					pred_coltype => 2, # valfloat
				       });
    }
    if( $label =~ /^(desig|loc|plain)$/ )
    {
	return $class->get_by_node_rec({
					label   => $1,
					node    => $special_id->{$1},
					pred_coltype => 5, # valtext
				       });
    }

    my $sql = 'select * from node where ';

    if( $label =~ /^-\d+$/ )
    {
	return $this->get_by_anything( $special_label->{$label}, $args );
    }
    elsif( $label =~ /^\d+$/ )
    {
	$sql .= 'node = ?';
    }
    else
    {
	$sql .= 'label = ?';
    }

    my $req = $Para::Frame::REQ;

    my $rec;
    eval
    {
	my $sth = $Rit::dbix->dbh->prepare($sql);
	$sth->execute($label);
	$rec = $sth->fetchrow_hashref;
	$sth->finish;
    } or return $Rit::dbix->report_error([$label]);

    if( $no_list )
    {
	if( $rec )
	{
	    return $class->get_by_node_rec( $rec );
	}
	else
	{
	    return is_undef;
	}
    }
    else
    {
	if( $rec )
	{
	    return Rit::Base::List->new([$class->get_by_node_rec( $rec )]);
	}
	else
	{
	    return Rit::Base::List->new([]);
	}
    }
}


#######################################################################

=head2 get_by_anything

=cut

sub get_by_anything
{
    my $args = {'return_single_value' => 1};

    my( $node ) = $_[0]->find_by_anything($_[1], $args);

    if( $node )
    {
#	debug "$_[0] -> get_by_anything($_[1])";
	return $node;
    }
    else
    {
	confess "No such predicate $_[1] in DB\n";
    }
}


#######################################################################

=head2 init

=cut

sub init
{
    my( $pred, $node_rec ) = @_;

    $pred->initiate_node( $node_rec );

#    debug "Pred coltype of $pred->{label} is $pred->{coltype}";

    return $pred;
}

#######################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $pred, $class_old ) = @_;

    $pred->set_coltype_from_range;
}

#######################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $pred, $arc, $pred_name, $args ) = @_;

    if( $pred_name eq 'range' )
    {
	# Update cache first # <- HERE !!


	$pred->set_coltype_from_range;
    }
}

#######################################################################

=head2 set_coltype_from_range

=cut

sub set_coltype_from_range
{
    my( $pred ) = @_;

    if( my $range = $pred->range )
    {
	my $valtype_id = $range->id;
	my $coltype = Rit::Base::Literal::Class->
	  coltype_by_valtype_id( $valtype_id ) || 'obj';
	my $coltype_id = Rit::Base::Literal::Class->
	  coltype_id_by_coltype( $coltype );
	$pred->set_coltype( $coltype_id );
    }
}

#######################################################################

=head2 set_coltype

  $n->set_coltype( $coltype_id )

=cut

sub set_coltype
{
    my( $pred, $coltype_new ) = @_;

    my $coltype_old = $pred->{'coltype'} || '';
    $coltype_new ||= '';

    if( $coltype_old ne $coltype_new )
    {
	if( $coltype_old )
	{
	    confess "Can't change a predicate from one coltype ($coltype_old) to another ($coltype_new)";
	}

	debug "Pred $pred->{id} coltype set to '$coltype_new'";
	$pred->{'coltype'} = $coltype_new;
	$pred->mark_updated;
    }

    return $coltype_new;
}


#######################################################################

=head2 find_class

=cut

sub find_class
{
    return "Rit::Base::Pred";
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::List>,
L<Rit::Base::Search>

=cut
