package RDF::Base::Arc::List;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Arc::List

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::List );

use Carp qw(carp croak cluck confess);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump  );

use RDF::Base::Utils qw( is_undef valclean query_desig parse_propargs );

=head1 DESCRIPTION

Inherits from L<RDF::Base::List>

=cut

##############################################################################

=head2 active

  $l->active

Returns: A new list with the arcs that are L<RDF::Base::Arc/active>

=cut

sub active
{
    $_[0]->new([grep $_->active, @{$_[0]}]);
}

##############################################################################

=head2 direct

  $l->direct

Returns: A new list with the arcs that are L<RDF::Base::Arc/direct>

=cut

sub direct
{
    $_[0]->new([grep $_->direct, @{$_[0]}]);
}

##############################################################################

=head2 adirect

  $l->adirect

Returns: A new list with the arcs that are L<RDF::Base::Arc/active>
and L<RDF::Base::Arc/direct>

=cut

sub adirect
{
    $_[0]->new([grep $_->direct, grep $_->active, @{$_[0]}]);
}

##############################################################################

=head2 submitted

  $l->submitted

Returns: A new list with the arcs that are L<RDF::Base::Arc/submitted>

=cut

sub submitted
{
    $_[0]->new([grep $_->submitted, @{$_[0]}]);
}

##############################################################################

=head2 is_new

  $l->is_new

Returns: A new list with the arcs that are L<RDF::Base::Arc/is_new>

=cut

sub is_new
{
    $_[0]->new([grep $_->is_new, @{$_[0]}]);
}

##############################################################################

=head2 old

  $l->old

Returns: A new list with the arcs that are L<RDF::Base::Arc/old>

=cut

sub old
{
    $_[0]->new([grep $_->old, @{$_[0]}]);
}

##############################################################################

=head2 inactive

  $l->inactive

Returns: A new list with the arcs that are L<RDF::Base::Arc/inactive>

=cut

sub inactive
{
    $_[0]->new([grep $_->inactive, @{$_[0]}]);
}

##############################################################################

=head2 indirect

  $l->indirect

Returns: A new list with the arcs that are L<RDF::Base::Arc/indirect>

=cut

sub indirect
{
    $_[0]->new([grep $_->indirect, @{$_[0]}]);
}

##############################################################################

=head2 not_submitted

  $l->not_submitted

Returns: A new list with the arcs that are L<RDF::Base::Arc/not_submitted>

=cut

sub not_submitted
{
    $_[0]->new([grep $_->not_submitted, @{$_[0]}]);
}

##############################################################################

=head2 explicit

  $l->explicit

Returns: A new list with the arcs that are L<RDF::Base::Arc/explicit>

=cut

sub explicit
{
    $_[0]->new([grep $_->explicit, @{$_[0]}]);
}

##############################################################################

=head2 implicit

  $l->implicit

Returns: A new list with the arcs that are L<RDF::Base::Arc/implicit>

=cut

sub implicit
{
    $_[0]->new([grep $_->implicit, @{$_[0]}]);
}

##############################################################################

=head2 not_new

  $l->not_new

Returns: A new list with the arcs that are L<RDF::Base::Arc/not_new>

=cut

sub not_new
{
    $_[0]->new([grep $_->not_new, @{$_[0]}]);
}

##############################################################################

=head2 not_old

  $l->not_old

Returns: A new list with the arcs that are L<RDF::Base::Arc/not_old>

=cut

sub not_old
{
    $_[0]->new([grep $_->not_old, @{$_[0]}]);
}

##############################################################################

=head2 not_disregarded

  $l->not_disregarded

Returns: A new list with the arcs that are L<RDF::Base::Arc/not_disregarded>

=cut

sub not_disregarded
{
    $_[0]->new([grep $_->not_disregarded, @{$_[0]}]);
}

##############################################################################

=head2 disregarded

  $l->disregarded

Returns: A new list with the arcs that are L<RDF::Base::Arc/disregarded>

=cut

sub disregarded
{
    $_[0]->new([grep $_->disregarded, @{$_[0]}]);
}

##############################################################################

=head2 subjs

  $l->subjs

Returns: A new list with the subjs

=cut

sub subjs
{
    RDF::Base::List->new([map $_->subj, @{$_[0]}]);
}

##############################################################################

=head2 vals

  $l->vals

(values() is taken as a perl function)

Returns: A new list with the values

=cut

sub vals
{
    RDF::Base::List->new([map $_->value, @{$_[0]}]);
}

##############################################################################

=head2 preds

  $l->preds

Returns: A new list with the preds

=cut

sub preds
{
    RDF::Base::Pred::List->new([map $_->pred, @{$_[0]}]);
}

##############################################################################

=head2 meets_proplim

  $l->meets_proplim($proplim, \%args)

Not implemented

=cut

sub meets_proplim
{
    confess "not implemented";
}

##############################################################################

=head2 meets_arclim

  $l->meets_arclim($arclim)

Returns: A new list with the arcs that meets the arclim

=cut

sub meets_arclim
{
    my( $l, $arclim ) = @_;

    $arclim = RDF::Base::Arc::Lim->parse($arclim);

    unless( @$arclim )
    {
	return $l;
    }

    my @arcs;

    my( $arc, $error ) = $l->get_first;
    while(! $error )
    {
	if( $arc->meets_arclim( $arclim ) )
	{
	    CORE::push @arcs, $arc;
	}

	( $arc, $error ) = $l->get_next;
    }

    return $l->new(\@arcs);
}

##############################################################################

=head2 unique_arcs_prio

  $list->unique_arcs_prio( \@arcproperties )

Example:

  $list->unique_arcs_prio( ['new','submitted','active'] )

Returns:

A List object with arc duplicates filtered out

=cut

sub unique_arcs_prio
{
    my( $list, $sortargs_in ) = @_;

    my $sortargs = RDF::Base::Arc::Lim->parse($sortargs_in);

    # $points->{ $commin_id }->[ $passed_order ] = $arc

#    debug "Sorting out duplicate arcs";


    my %points;

    my( $arc, $error ) = $list->get_first;
    while(! $error )
    {
	unless( $arc->is_arc ) # Might have been recently removed
	{
	    cluck "Not arc in unique_arcs_prio; $error - ".$arc->sysdesig;
	    next;
	}

#	my $cid = $arc->common_id;
#	my $sor = $sortargs->sortorder($arc);
#	debug "Sort $sor: ".$arc->sysdesig;
#	$points{ $cid }[ $sor ] = $arc;
	$points{ $arc->common_id }[ $sortargs->sortorder($arc) ] = $arc;
    }
    continue
    {
	( $arc, $error ) = $list->get_next;
    };

#    debug "unique_arcs_prio";
#    debug query_desig(\%points);
#    debug "----------------";

    my @arcs;
    foreach my $group ( values %points )
    {
	foreach my $arc (@$group)
	{
	    if( $arc )
	    {
		CORE::push @arcs, $arc;
		last;
	    }
	}
    }

    return RDF::Base::Arc::List->new( \@arcs );
}


##############################################################################

=head2 arc_active_on_date

  $list->arc_active_on_date( $date )

  $args = parse_propargs({ arc_active_on_date => $date })

See also L<RDF::Base::Arc/version_by_date>

Returns: A L<RDF::Base::Arc::List> with the active arc, or an empty
list if none found.

=cut

sub arc_active_on_date
{
    my( $list, $date ) = @_;

    my @arcs;

    my( $arc, $error ) = $list->get_first;
    while(! $error )
    {
	next unless $arc->activated <= $date;
	if( $arc->deactivated )
	{
	    next unless $arc->deactivated > $date;
	}
	next if $arc->is_removal;

#	debug "Found an arc active on $date: ".$arc->sysdesig;
	push @arcs, $arc;
    }
    continue
    {
	( $arc, $error ) = $list->get_next;
    };

    return RDF::Base::Arc::List->new(\@arcs);
}


##############################################################################

=head2 as_rdf

=cut

sub as_rdf
{
    my( $l ) = shift;

    my $out = "";

    my $predl = $l->get_first_nos->pred->label;
    $out .= "<rb:$predl>\n";
    $out .= "<rdf:Bag>\n";

    foreach my $arc ( $l->as_array )
    {
        debug "  + ".$arc->sysdesig;
        my $val = $arc->value;
        if( $val->is_literal )
        {
            my $type = $val->this_valtype;
            my $val_out = CGI->escapeHTML($val);
            my $type_label = $type->label || $type->id;
            $out .= qq(<rdf:li rdf:datatype="$type_label">$val_out</rdf:li>\n);
        }
        else
        {
            my $res_out = $val->label || $val->id;
            $out .= qq(<rdf:li rdf:resource="$res_out"/>);
        }
    }

    $out .= "</rdf:Bag>\n";
    $out .= "</rb:$predl>\n";

    return $out;
}


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
