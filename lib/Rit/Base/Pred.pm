#  $Id$  -*-cperl-*-
package Rit::Base::Pred;
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

Rit::Base::Pred

=cut

use Carp qw( cluck confess carp croak );
use strict;
use Time::HiRes qw( time );
use Scalar::Util qw( refaddr );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

use Rit::Base::List;
use Rit::Base::Utils qw( valclean translate is_undef parse_propargs );
use Rit::Base::Literal::String;
use Rit::Base::Constants qw( $C_predicate );


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
 label => -11,
 created => -12,
 updated => -13,
 owned_by => -14,
 read_access => -15,
 write_access => -16,
 created_by => -17,
 updated_by => -18,
};

our $special_label = { reverse %$special_id };

=head1 DESCRIPTION

Represents preds.

Inherits from L<Rit::Base::Resource>.

=cut




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

=cut

sub valtype
{
    my( $pred ) = @_;

    if( my $range_arcs = $pred->{'relarc'}{'range'} )
    {
	return $range_arcs->[0]{'value'}; # Optimization shortcut
    }

    if( my $range = $pred->first_prop('range') )
    {
#	debug datadump($pred,3);
	return $range;
    }
    else
    {
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

#######################################################################

=head2 coltype_id

  $p->coltype_id()

Returns: An integer as a scalar string

=cut

sub coltype_id
{
    unless( $_[0]->{'coltype'} )
    {
	confess "Pred ".$_[0]->sysdesig." is missing a coltype";
    }

    return $_[0]->{'coltype'};
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
    elsif( $label =~ /^(desig|loc|plain|label)$/ )
    {
	push @new, $class->get_by_node_rec({
					    label   => $1,
					    node    => $special_id->{$1},
					    pred_coltype => 5, # valtext
					   });
    }
    elsif( $label =~ /^(created|updated)$/ )
    {
	push @new, $class->get_by_node_rec({
					    label   => $1,
					    node    => $special_id->{$1},
					    pred_coltype => 4, # valdate
					   });
    }
    elsif( $label =~ /^(owned_by|read_access|write_access|created_by|updated_by)$/ )
    {
	push @new, $class->get_by_node_rec({
					    label   => $1,
					    node    => $special_id->{$1},
					    pred_coltype => 1, # obj
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

Data from node rec mus always be awailible. Thus always load the node
rec.

=cut

sub init
{
    my( $pred, $node_rec ) = @_;

    $pred->initiate_node($node_rec);

    unless( $pred->{coltype} )
    {
	confess "Node $pred->{id} is not a predicate";
    }

#    debug "Pred coltype of $pred->{label} is $pred->{coltype}";

    return $pred;
}

#######################################################################

=head2 get_by_node_rec

Reimplements this here because we can't give the node_rec to init for
any class.

=cut

sub get_by_node_rec
{
    my( $this, $rec ) = @_;

    my $id = $rec->{'node'} or
      confess "get_by_node_rec misses the node param: ".datadump($rec,2);
    return $Rit::Base::Cache::Resource{$id} ||
      $this->new($id)->init($rec);
}

#######################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $pred, $class_old, $args_in ) = @_;

    # This initiates the node, if existing
    unless( $pred->label )
    {
	confess "A pred must have a label";
    }

    $pred->on_new_range($args_in);
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

    $pred->on_new_range($args_in);
}

#######################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $pred, $arc, $pred_name, $args_in ) = @_;

    if( $pred_name eq 'range' )
    {
	$pred->on_new_range($args_in);
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
	$pred->on_new_range($args_in);
    }
}

#######################################################################

=head2 on_new_range

  $pred->on_new_range( \%args )

=cut

sub on_new_range
{
    my( $pred, $args_in ) = @_;

    debug "Updating arcs for the new range";

    my $C_resource = Rit::Base::Constants->get('resource');

    my( $range_new, $range_old );
    if( my $range_arc = $pred->first_arc('range') )
    {
	$range_new = $range_arc->value;
	if( my $prev_arc = $range_arc->previous_active_version )
	{
	    $range_old = $prev_arc->value;
	}

	unless( $range_new ) # A removal arc?
	{
	    $range_new = $C_resource;
	}
    }

    $range_new ||= $pred->valtype;
    $range_old ||= $C_resource;
    my $old_coltype_id = $pred->{'coltype'} || 0;

    # Updating coltype
    if( $old_coltype_id != $range_new->coltype_id )
    {
	$pred->set_coltype( $range_new->coltype_id, $args_in );
    }


    # Range unchanged?
    if( $range_old->equals($range_new) )
    {
	return;
    }


    # was the old range more specific?
    if( $range_old->scof($range_new) )
    {
	# This is compatible with all existing arcs
	return;
    }


    # This is a big change. Make sure this is what is wanted
    #
    $pred->vacuum_pred_arcs( $args_in );

    return;
}

#######################################################################

=head2 vacuum_pred_arcs

  $pred->vacuum_pred_arcs( \%args )

Special args:

  convert_prop_to_value

For now, we just ignore failed vacuums...

TODO: Handle failed vacuums

=cut

sub vacuum_pred_arcs
{
    my( $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $arcs = $pred->active_arcs;

    my $size = $arcs->size;
    debug "Vacuuming $size arcs";

    my $remove_faulty = $args->{'remove_faulty'} || 0;

    my( $arc, $error ) = $arcs->get_first;
    while(! $error )
    {
	eval
	{
	    $arc->vacuum( $args );
	};
	if( my $err = catch(['validation']) )
	{
	    debug 1, $err->as_string;
	    if( $remove_faulty )
	    {
		$arc->remove({'activate_new_arcs'=>1});
	    }
	}
    }
    continue
    {
	( $arc, $error ) = $arcs->get_next;
    };

    return;
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

#    debug "Set coltype for pred ".$pred->sysdesig. " ".refaddr($pred);
    debug "Set coltype for pred ".refaddr($pred);

    unless( $pred->{'label'} )
    {
	debug datadump($pred,2);
	confess "Has this been initiated as a pred?!";
    }
#    $pred->initiate_node;

    my $coltype_old_id = $pred->{'coltype'} || 0;
    $coltype_new_id ||= 0;

    if( $coltype_new_id !~ /^\d+$/ )
    {
	$coltype_new_id = Rit::Base::Literal::Class->
	  coltype_id_by_coltype( $coltype_new_id );
    }

    if( $coltype_old_id != $coltype_new_id )
    {
	if( my $range = $pred->first_prop('range',undef,$args) )
	{
	    if( $range->coltype_id != $coltype_new_id )
	    {
		confess "Caller has to set the range first";
	    }
	}

	my $pred_id = $pred->id;

	debug "Pred $pred_id coltype set to '$coltype_new_id'";
	$pred->{'coltype'} = $coltype_new_id;
	$pred->mark_updated;
	$res->changes_add();

	if( $coltype_old_id )
	{
	    debug "Changing coltype id from $coltype_old_id to $coltype_new_id!!!";
	    debug "EXISTING ARCS MUST BE VACUUMED";
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

    $pred->on_new_range( $args_in );
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

=head2 this_valtype

=cut

sub this_valtype
{
    return $C_predicate;
}


#######################################################################

=head2 list_class

=cut

sub list_class
{
    return "Rit::Base::Pred::List";
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
