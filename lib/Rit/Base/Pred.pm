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
use Rit::Base::Utils qw( valclean translate is_undef parse_propargs );
use Rit::Base::Literal::String;


### Inherit
#
use base qw( Rit::Base::Resource );


use constant R => 'Rit::Base::Resource';


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

=head2 is_pred

Is this a pred? Yes.

Returns: 1

=cut

sub is_pred { 1 };


#########################################################################

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
    my( @new );

#    warn "New pred $label\n"; ### DEBUG

    if( ref $label )
    {
	if( UNIVERSAL::isa( $label, 'Rit::Base::Literal') )
	{
	    $label = $label->literal;
	}
	elsif( UNIVERSAL::isa( $label, 'Rit::Base::Pred') )
	{
	    return Rit::Base::List->new([$label]);
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

    $label or confess "get_by_anything got empty label";


    # TODO: Insert special predicates subj, pred, obj, coltype

    if( $label =~ /^-\d+$/ )
    {
	$label = $special_label->{$label};
    }


    # Special properties
    if( $label =~ /^(id|score|random)$/ )
    {
	push @new, $class->get_by_node_rec({
					    label   => $1,
					    node    => $special_id->{$1},
					    pred_coltype => 2, # valfloat
					   });
    }
    elsif( $label =~ /^(desig|loc|plain)$/ )
    {
	push @new, $class->get_by_node_rec({
					    label   => $1,
					    node    => $special_id->{$1},
					    pred_coltype => 5, # valtext
					   });
    }
    elsif( $label =~ /^\d+$/ )
    {
	# Check that this is a pred is done in init()
	push @new, $this->get($label);
    }
    elsif( ref $label )
    {
	my $list = $this->SUPER::find_by_anything($label);
	foreach my $pred ( $list->as_array )
	{
	    unless( $pred->is_pred )
	    {
		confess "$pred is not a predicate";
	    }
	}
	return $list;
    }
    else
    {
	# Check that this is a pred is done in init()
	push @new, $this->get_by_label($label);
    }

    return Rit::Base::List->new(\@new);
}


#######################################################################

=head2 init

=cut

sub init
{
    my( $pred, $node_rec ) = @_;

    $pred->initiate_node( $node_rec );

    unless( $pred->{coltype} )
    {
	confess "Node $pred->{id} is not a predicate";
    }

#    debug "Pred coltype of $pred->{label} is $pred->{coltype}";

    return $pred;
}

#######################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $pred, $class_old, $args_in ) = @_;

    $pred->set_coltype_from_range($args_in);
}

#######################################################################

=head2 on_unbless

=cut

sub on_unbless
{
    my( $pred, $class_new, $args_in ) = @_;

    if( $pred->has_arcs )
    {
	confess "You can't remove a pred used in arcs";
    }

    $pred->set_coltype_from_range($args_in);
}

#######################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $pred, $arc, $pred_name, $args_in ) = @_;

    if( $pred_name eq 'range' )
    {
	$pred->update_arcs_for_new_range($arc, $args_in);
    }
}

#######################################################################

=head2 on_arc_del

=cut

sub on_arc_del
{
    my( $pred, $arc, $pred_name, $args_in ) = @_;

    if( $pred_name eq 'range' )
    {
	$pred->update_arcs_for_new_range($arc, $args_in);
    }
}

#######################################################################

=head2 update_arcs_for_new_range

  $pred->update_arcs_for_new_range( \%args )

=cut

sub update_arcs_for_new_range
{
    my( $pred, $arc, $args_in ) = @_;

    $pred->set_coltype_from_range($args_in);

    unless( $arc->replaces_id )
    {
	# No previous value
	return;
    }

    my $range_old = $arc->replaces->value;
    my $range_new = $pred->valtype; # may fall back on default

    # was the old range more specific?
    if( $range_old->scof($range_new) )
    {
	# This is compatible with all existing arcs
	return;
    }

    # All active existing arcs must be upgraded

    unless( $pred->has_active_arcs )
    {
	# No active existing arcs to worry about
	return;
    }

    # This is a big change. Make sure this is what is wanted

    $pred->vacuum_pred_arcs( $args_in );

    return;
}

#######################################################################

=head2 vacuum_pred_arcs

  $pred->vacuum_pred_arcs( \%args )

=cut

sub vacuum_pred_arcs
{
    my( $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $arcs = $pred->active_arcs;

    my $size = $arcs->size;
    debug "Vacuuming $size arcs";

    my( $arc, $error ) = $arcs->get_first;
    while(! $error )
    {
	$arc->vacuum( $args );
    }
    continue
    {
	( $arc, $error ) = $arcs->get_next;
    };

    return;
}

#######################################################################

=head2 set_coltype_from_range

  $pred->set_coltype_from_range( \%args )

=cut

sub set_coltype_from_range
{
    my( $pred, $args_in ) = @_;

    debug "Setting coltype from range for pred $pred->{id}";
    if( my $range = $pred->range )
    {
	debug "  Range is $range->{id}";
	my $coltype = $range->coltype;
	debug "  found coltype $coltype" if $coltype;
	$pred->set_coltype( $coltype, $args_in );
    }
}

#######################################################################

=head2 set_coltype

  $n->set_coltype( $coltype_id, \%args )

  $n->set_coltype( $coltype, \%args )

returns: The new coltype id

=cut

sub set_coltype
{
    my( $pred, $coltype_new_id, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $coltype_old_id = $pred->{'coltype'} || 0;
    $coltype_new_id ||= 0;

    if( $coltype_new_id !~ /^\d+$/ )
    {
	$coltype_new_id = Rit::Base::Literal::Class->
	  coltype_id_by_coltype( $coltype_new_id );
    }

    if( $coltype_old_id != $coltype_new_id )
    {
	my $pred_id = $pred->id;

	debug "Pred $pred_id coltype set to '$coltype_new_id'";
	$pred->{'coltype'} = $coltype_new_id;
	$pred->mark_updated;
	$res->changes_add();

	if( $coltype_old_id )
	{
	    my $coltype_old = Rit::Base::Literal::Class->
	      coltype_by_coltype_id( $coltype_old_id );

	    my $coltype_new = Rit::Base::Literal::Class->
	      coltype_by_coltype_id( $coltype_new_id );

	    debug "Changing coltype from $coltype_old to $coltype_new!!!";

	    # TODO: now just checks for existance (limit 1)
	    #
	    my $st = "select * from arc where pred=$pred_id and $coltype_old is not null limit 1";
	    my $sth = $Rit::dbix->dbh->prepare($st);
	    $sth->execute();
	    while( my($rec) = $sth->fetchrow_hashref )
	    {
		my( $val ) = $rec->{ $coltype_old };
		if( defined $val )
		{
		    confess "I would have to transform $coltype_old value $val to $coltype_new";
		}
	    }
	    $sth->finish;
	}

    }

    return $coltype_new_id;
}


#######################################################################

=head2 vacuum

  $pred->vacuum( \%args )

=cut

sub vacuum
{
    my( $pred, $args_in ) = @_;

    $pred->set_coltype_from_range( $args_in );
    return $pred->SUPER::vacuum( $args_in );
}


#######################################################################

=head2 use_class

=cut

sub use_class
{
    return "Rit::Base::Pred";
}


#######################################################################

=head2 has_arcs

  $p->has_arcs

Retruns: true, if there is any arc that uses the pred

=cut

sub has_arcs
{
    # Any arcs with this pred?
    my $pred_id = $_[0]->id;
    my $st = "select 1 from arc where pred=$pred_id limit 1";
    my $sth = $Rit::dbix->dbh->prepare($st);
    $sth->execute();
    my($exist) = $sth->fetchrow_array;
    $sth->finish;

    return $exist ? 1 : 0;
}


#######################################################################

=head2 has_active_arcs

  $p->has_active_arcs

Retruns: true, if there is any active arc that uses the pred

=cut

sub has_active_arcs
{
    # Any arcs with this pred?
    my $pred_id = $_[0]->id;
    my $st = "select 1 from arc where pred=$pred_id and active is true limit 1";
    my $sth = $Rit::dbix->dbh->prepare($st);
    $sth->execute();
    my($exist) = $sth->fetchrow_array;
    $sth->finish;

    return $exist ? 1 : 0;
}


#######################################################################

=head2 active_arcs

  $p->active_arcs

Retruns: a L<Rit::Base::List> of arcs

=cut

sub active_arcs
{
    my( $pred, $args_in ) = @_;

    my $largs =
    {
     'materializer' => \&Rit::Base::List::materialize_by_rec,
    };

    my $pred_id = $pred->id;
    my $st = "select * from arc where pred=$pred_id and active is true";
    my $sth = $Rit::dbix->dbh->prepare($st) or die;
    $sth->execute() or die;

    my @list;
    my $i=0;
    while( my $rec = $sth->fetchrow_hashref )
    {
	push @list, $rec;
    }
    $sth->finish;

    return Rit::Base::List->new( \@list, $largs );
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
