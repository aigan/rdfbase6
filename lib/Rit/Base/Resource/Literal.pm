#  $Id$  -*-cperl-*-
package Rit::Base::Resource::Literal;
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

Rit::Base::Resource::Literal

=cut

use strict;
use Carp qw( cluck confess carp shortmess longmess );
use Scalar::Util qw( refaddr );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Widget qw( label_from_params );

use Rit::Base::Literal::String;
use Rit::Base::Literal::Time;
use Rit::Base::Literal::URL;
use Rit::Base::Literal::Email::Address;
use Rit::Base::Arc::Lim;
use Rit::Base::Pred;
use Rit::Base::List;

use Rit::Base::Constants qw( $C_resource );

use Rit::Base::Utils qw( is_undef valclean truncstring parse_propargs
                         convert_query_prop_for_creation query_desig );

### Inherit
#
use base qw( Rit::Base::Resource );


=head1 DESCRIPTION

Represents a Literal resource (value node).

Inherits from L<Rit::Base::Resource>.

=head2 notes

121[122] 123 -name-> [124]"Apa"
125[126] 124 -is_of_language-> sv
127[122] 123 -name-> [124]"Bepa"

"Apa" isa Rit::Base::Literal
[124] isa Rit::Base::Resource::Literal

$nlit = $R->get(124);
$lit = $nlit->value('active');
$nlit = $lit->node;
print $lit->plain; # Bepa

=cut


#######################################################################

=head2 init

  $n->init( $rec, \%args )

=cut

sub init
{
    my( $node, $rec, $args ) = @_;

    $args ||= {};

    my $revrecs = delete $node->{'revrecs'};
    unless( $revrecs )
    {
	$revrecs = [];
	my $sth_id = $Rit::dbix->dbh->prepare("select * from arc where obj=?");
	$sth_id->execute($node->id);
	while( $rec = $sth_id->fetchrow_hashref )
	{
	    push @$revrecs, $rec;
	}
    }

    # Not bothering about large number of revrecs...

    my @revarc_active;
    my @revarc_inactive;
    my $cnt = 0;
    foreach my $rec (@$revrecs)
    {
	my $arc = Rit::Base::Arc->get_by_rec($rec);
	if( $arc->active )
	{
	    push @revarc_active, $arc;
	}
	else
	{
	    push @revarc_inactive, $arc;
	}
    }

    $node->{'revarc_active'} = \@revarc_active;
    $node->{'revarc_inactive'} = \@revarc_inactive;

    return $node;
}


#######################################################################

=head2 is_value_node

  $n->is_value_node()

Returns true if this node is a Literal Resource (aka value node).

Returns: 1

=cut

sub is_value_node
{
    return 1;
}


#######################################################################

=head2 literal_list

  $n->literal_list( \%args )

The literal value that this object represents.  This asumes that the
object is a Literal Resource (aka Value Resource).  Only use this then you
know that this L</is_value_node>.

=cut

sub literal_list
{
    my( $node, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    my @arcs;

    if( $active and $inactive )
    {
	@arcs = grep $_->meets_arclim($arclim),
	  @{$node->{'revarc_active'}},
	    @{$node->{'revarc_inactive'}};
    }
    elsif( $active )
    {
	@arcs = grep $_->meets_arclim($arclim),
	  @{$node->{'revarc_active'}};
    }
    elsif( $inactive )
    {
	@arcs = grep $_->meets_arclim($arclim),
	  @{$node->{'revarc_inactive'}};
    }

    if( my $uap = $args->{unique_arcs_prio} )
    {
	@arcs = Rit::Base::Arc::List->new(\@arcs)->
	  unique_arcs_prio($uap)->as_array;
    }

    return Rit::Base::List->new([map $_->value, @arcs]);
}


#######################################################################

=head2 first_literal

  $n->first_literal( \%args )

=cut

sub first_literal
{
    return shift->literal_list(@_)->get_first_nos();
}


#######################################################################

=head2 literal

  $n->literal( \%args )

=cut

sub literal
{
    my $values = shift->literal_list(@_);

    unless( $values )
    {
	return is_undef;
    }

    if( $values->size == 1 ) # Return Resource, or undef if no such element
    {
	return $values->get_first_nos;
    }
    elsif( $values->size > 1 ) # More than one element
    {
	return $values;  # Returns list
    }
    else
    {
	return is_undef;
    }
}


#########################################################################

=head2 this_valtype

  $node->this_valtype( \%args )

This would be the same as the C<is> property of this resource. But it
must only have ONE value. It's important for literal values.

This method will return the literal valtype for value resoruces and
return the C<resource> resource for other resources.

See also: L<Rit::Base::Literal/this_valtype>, L</is_value_node>.

=cut

sub this_valtype
{
    my( $node, $args_in ) = @_;

    debug " ---------> CHECKME, valtype for $node->{id}";
    return $C_resource;
}


#######################################################################
#
#=head2 lit_revarc
#
#  $literal->lit_revarc
#
#Return the arc this literal is a part of.
#
#See also: L</arc> and L</revarc>
#
#=cut
#
#sub lit_revarc
#{
#    $_[0]->{'literal_arc'} || is_undef;
#}
#
#
#######################################################################

=head3 revlist

=cut

sub revlist
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = Rit::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my( $active, $inactive ) = $arclim->incl_act;
	my @arcs;

	if( $active )
	{
	    foreach my $arc (@{$node->{'revarc_active'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	if( $inactive )
	{
	    foreach my $arc (@{$node->{'revarc_inactive'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    @arcs = Rit::Base::Arc::List->new(\@arcs)->
	      unique_arcs_prio($uap)->as_array;
	}

	if( my $arclim2 = $args->{'arclim2'} )
	{
	    my $args2 = {%$args};
	    $args2->{'arclim'} = $arclim2;
	    delete $args2->{'arclim2'};

	    $args = $args2;
	}

	return Rit::Base::List->new([grep $_->meets_proplim($proplim,$args),
				     map $_->subj, @arcs ]);
    }
    else
    {
	return $node->revlist_preds( $proplim, $args );
    }
}


#######################################################################

=head3 revlist_preds

=cut

sub revlist_preds
{
    my( $node, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $proplim )
    {
	die "proplim not implemented";
    }

    my( $active, $inactive ) = $arclim->incl_act;

    $node->initiate_rev( $proplim, $args );

    my %preds_name;
    if( $active )
    {
	foreach my $arc (@{$node->{'revarc_active'}})
	{
	    if( $arc->meets_arclim($arclim) )
	    {
		$preds_name{$arc->pred->plain} ++;
	    }
	}
    }

    if( $inactive )
    {
	foreach my $arc (@{$node->{'revarc_inactive'}})
	{
	    if( $arc->meets_arclim($arclim) )
	    {
		$preds_name{$arc->pred->plain} ++;
	    }
	}
    }

    # Only handles pred nodes
    my @preds = map Rit::Base::Pred->get_by_label($_, $args), keys %preds_name;

    return Rit::Base::Pred::List->new(\@preds);
}


#######################################################################

=head3 first_revprop

=cut

sub first_revprop
{
    return shift->revlist(@_)->get_first_nos;
}


#######################################################################

=head3 revcount

=cut

sub revcount
{
    my( $node, $tmpl, $args_in ) = @_;

    if( ref $tmpl and ref $tmpl eq 'HASH' )
    {
	throw('action',"count( \%tmpl, ... ) not implemented");
    }

    my $list = $node->revlist($tmpl, $args_in);
    return $list->size;
}


#######################################################################

=head3 set_label

=cut

sub set_label
{
    confess "Setting a label on a literal resource is not allowed";
}


#######################################################################

=head3 revarc_list

=cut

sub revarc_list
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = Rit::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my @arcs;

	if( $active )
	{
	    foreach my $arc (@{$node->{'revarc_active'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	if( $inactive )
	{
	    foreach my $arc (@{$node->{'revarc_inactive'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	my $lr = Rit::Base::Arc::List->new(\@arcs);

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    $lr = $lr->unique_arcs_prio($uap);
	}

	if( $proplim and (ref $proplim eq 'HASH' ) and keys %$proplim )
	{
	    $lr = $lr->find($proplim, $args);
	}

	return $lr;
    }
    else
    {
	$node->initiate_rev($proplim, $args);

	if( $proplim )
	{
	    die "proplim not implemented";
	}

	my @arcs;
	if( $active )
	{
	    push @arcs, @{$node->{'revarc_active'}};
	}

	if( $inactive )
	{
	    push @arcs, @{$node->{'revarc_inactive'}};
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    return Rit::Base::Arc::List->new(\@arcs)->unique_arcs_prio($uap);
	}
	else
	{
	    return Rit::Base::Arc::List->new(\@arcs);
	}
    }
}


#######################################################################

=head3 first_revarc

=cut

sub first_revarc
{
    return shift->revarc_list(@_)->get_first_nos;
}


#######################################################################

=head3 revarc

=cut

sub revarc
{
    return shift->lit_revarc(@_);
}


#######################################################################

=head3 vacuum

This vacuums both arcs and revarcs. Normal vacuum doesn't vacuum revarcs

=cut

sub vacuum
{
    my( $node, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $no_lim = Rit::Base::Arc::Lim->parse(['active','inactive']);
    foreach my $arc ( $node->arc_list( undef, undef, $no_lim )->as_array )
    {
	next if $arc->disregard;
	$Para::Frame::REQ->may_yield;
	$arc->vacuum( $args );
    }

    foreach my $arc ( $node->revarc_list( undef, undef, $no_lim )->as_array )
    {
	next if $arc->disregard;
	$Para::Frame::REQ->may_yield;
	$arc->vacuum( $args );
    }

    return $node;
}


#######################################################################

=head3 merge_node

=cut

sub merge_node
{
    confess "merging a literal resource?!";
}


#######################################################################

=head3 link_paths

=cut

sub link_paths
{
    return [];
}


#######################################################################

=head3 wu

=cut

sub wu
{
    my( $node, $pred_name, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    return $node->first_literal($args)->wu($pred_name,$args);
}


#######################################################################

=head3 tree_select_widget

=cut

sub tree_select_widget
{
    return "";
}


#######################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id, if existing.

=cut

sub sysdesig  # The designation of obj, including node id
{
    return shift->id.": <value>";
}


#########################################################################

=head3 wdirc

=cut

sub wdirc
{
    my( $node, $subj, $pred, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    return $node->first_literal($args)->wdirc($subj,$pred,$args);
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Literal>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
