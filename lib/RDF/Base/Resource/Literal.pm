package RDF::Base::Resource::Literal;
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

RDF::Base::Resource::Literal

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Resource );

use Carp qw( cluck confess carp shortmess longmess );
use Scalar::Util qw( refaddr );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Widget qw( label_from_params );

use RDF::Base::Literal::String;
use RDF::Base::Literal::Time;
use RDF::Base::Literal::URL;
use RDF::Base::Literal::Email::Address;
use RDF::Base::Arc::Lim;
use RDF::Base::Pred;
use RDF::Base::List;

use RDF::Base::Constants qw( $C_resource $C_literal );

use RDF::Base::Utils qw( is_undef valclean truncstring parse_propargs
                         convert_query_prop_for_creation query_desig );


=head1 DESCRIPTION

Represents a Literal resource (value node).

Inherits from L<RDF::Base::Resource>.

=head2 notes

121[122] 123 -name-> [124]"Apa"
125[126] 124 -is_of_language-> sv
127[122] 123 -name-> [124]"Bepa"

"Apa" isa RDF::Base::Literal
[124] isa RDF::Base::Resource::Literal

$nlit = $R->get(124);
$lit = $nlit->value('active');
$nlit = $lit->node;
print $lit->plain; # Bepa

=cut


##############################################################################

=head2 init

  $n->init( $rec, \%args )

=cut

sub init
{
    my( $node, $rec, $args ) = @_;

    $args ||= {};

#    debug "(re)initiating lit res $node->{id}";

    my $revrecs = delete $node->{'revrecs'};
    unless( $revrecs )
    {
	$revrecs = [];
	my $sth_id = $RDF::dbix->dbh->prepare("select * from arc where obj=?");
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
	my $arc = RDF::Base::Arc->get_by_rec($rec);
	if( $arc->active )
	{
#	    debug "  active: ".$arc->sysdesig;
	    push @revarc_active, $arc;
	}
	else
	{
	    push @revarc_inactive, $arc;
	}
    }

    $node->{'lit_revarc_active'} = \@revarc_active;
    $node->{'lit_revarc_inactive'} = \@revarc_inactive;

    return $node;
}


##############################################################################

=head2 is_value_node

  $n->is_value_node()

Returns true if this node is a Literal Resource (aka value node).

Returns: 1

=cut

sub is_value_node
{
    return 1;
}


##############################################################################

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

#    debug "Literal list using arclim: ".$arclim->sysdesig;

    my @arcs;

    if( $active and $inactive )
    {
#	debug "  active and inactive";
	@arcs = grep $_->meets_arclim($arclim),
	  @{$node->{'lit_revarc_active'}},
	    @{$node->{'lit_revarc_inactive'}};
    }
    elsif( $active )
    {
#	debug "  active";
	@arcs = grep $_->meets_arclim($arclim),
	  @{$node->{'lit_revarc_active'}};
    }
    elsif( $inactive )
    {
#	debug "  inactive";
	@arcs = grep $_->meets_arclim($arclim),
	  @{$node->{'lit_revarc_inactive'}};
    }

    if( my $uap = $args->{unique_arcs_prio} )
    {
#	debug "  unique_arcs_prio";
	@arcs = RDF::Base::Arc::List->new(\@arcs)->
	  unique_arcs_prio($uap)->as_array;
    }
    elsif( my $aod = $args->{arc_active_on_date} )
    {
	@arcs = RDF::Base::Arc::List->new(\@arcs)->
	  arc_active_on_date($aod)->as_array;
    }
#    debug 0, "literal arc list: ". join '/', map $_->id, @arcs;
    return RDF::Base::List->new([map $_->value, @arcs]);
}


##############################################################################

=head2 first_literal

  $n->first_literal( \%args )

Always returns the first created arc value that is active and direct.

Sort by id in order to use the original arc as a base of reference for
the value, in case that other arc points to the same node.

=cut

sub first_literal
{
    return $_[0]->lit_revarc($_[1])->{'value'} || is_undef;


#    return $_[0]->literal_list({arclim=>['adirect']})->sorted('lit_revarc.id')->get_first_nos();

#    my $list = shift->literal_list(@_);
#    debug "Returning first literal from list:";
#    foreach my $lit ($list->as_array ){debug " * ".$lit->sysdesig}
#    return $list->get_first_nos();

#    return shift->literal_list(@_)->get_first_nos();
}


##############################################################################

=hed2 lit_revarc

  $l->lit_revarc( \%args )

Return the arc this literal is a part of.

See also: L</arc> and L</revarc>

=cut

sub lit_revarc
{
#    debug "lit_revarc with arclim: $_[1]";

    if( defined $_[0]->{'literal_arc'} and
        not( $_[1] and @{$_[1]->{arclim}} ) )
    {
        return $_[0]->{'literal_arc'};
    }

#    debug "arclim ".datadump($#{$_[1]->{arclim}},1);

#    debug "Finding first arc for ".$_[0]->id;

    my $args = $_[1] || {arclim=>['adirect']};
    my $arclim = $args->{arclim} || ['adirect'];

    my $arcs = $_[0]->revarc_list(undef,undef,{arclim=>$arclim});
    my $lit_revarc = $arcs->get_first_nos();
    if( $lit_revarc )
    {
        while( my $arc = $arcs->get_next_nos )
        {
            $lit_revarc = $arc if $arc->id < $lit_revarc->id;
        }
    }
    else
    {
        $lit_revarc = is_undef;
    }
#    debug "  found ".$lit_revarc->id;
    unless( $_[1] and @{$_[1]->{arclim}} )
    {
        $_[0]->{'literal_arc'} = $lit_revarc;
    }

    return $lit_revarc;
}


##############################################################################

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

See also: L<RDF::Base::Literal/this_valtype>, L</is_value_node>.

=cut

sub this_valtype
{
    my( $node, $args_in ) = @_;

    debug " ---------> CHECKME, valtype for $node->{id}";
    return $C_literal;
}


##############################################################################

=head3 revlist

=cut

sub revlist
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'RDF::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = RDF::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my( $active, $inactive ) = $arclim->incl_act;
	my @arcs;

	if( $active )
	{
	    foreach my $arc (@{$node->{'lit_revarc_active'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	if( $inactive )
	{
	    foreach my $arc (@{$node->{'lit_revarc_inactive'}})
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
	    @arcs = RDF::Base::Arc::List->new(\@arcs)->
	      unique_arcs_prio($uap)->as_array;
	}
	elsif( my $aod = $args->{arc_active_on_date} )
	{
	    @arcs = RDF::Base::Arc::List->new(\@arcs)->
	      arc_active_on_date($aod)->as_array;
	}

	if( my $arclim2 = $args->{'arclim2'} )
	{
	    my $args2 = {%$args};
	    $args2->{'arclim'} = $arclim2;
	    delete $args2->{'arclim2'};

	    $args = $args2;
	}

	return RDF::Base::List->new([grep $_->meets_proplim($proplim,$args),
				     map $_->subj, @arcs ]);
    }
    else
    {
	return $node->revlist_preds( $proplim, $args );
    }
}


##############################################################################

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
	foreach my $arc (@{$node->{'lit_revarc_active'}})
	{
	    if( $arc->meets_arclim($arclim) )
	    {
		$preds_name{$arc->pred->plain} = $arc->pred;
	    }
	}
    }

    if( $inactive )
    {
	foreach my $arc (@{$node->{'lit_revarc_inactive'}})
	{
	    if( $arc->meets_arclim($arclim) )
	    {
		$preds_name{$arc->pred->plain} = $arc->pred;
	    }
	}
    }

    my @preds = values %preds_name;

    return RDF::Base::Pred::List->new(\@preds);
}


##############################################################################

=head3 first_revprop

=cut

sub first_revprop
{
    return shift->revlist(@_)->get_first_nos;
}


##############################################################################

=head3 revcount

=cut

sub revcount
{
    my( $node, $tmpl, $args_in ) = @_;

    if( ref $tmpl and ref $tmpl eq 'HASH' )
    {
	throw('action',"count( \%tmpl, ... ) not implemented");
    }

    my $list = $node->revlist($tmpl, undef, $args_in);
    return $list->size;
}


##############################################################################

=head3 set_label

=cut

sub set_label
{
    confess "Setting a label on a literal resource is not allowed";
}


##############################################################################

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
	if( UNIVERSAL::isa($pred_in,'RDF::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = RDF::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my @arcs;

	if( $active )
	{
	    foreach my $arc (@{$node->{'lit_revarc_active'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	if( $inactive )
	{
	    foreach my $arc (@{$node->{'lit_revarc_inactive'}})
	    {
		if( $arc->pred->equals($pred) )
		{
		    push @arcs, $arc;
		}
	    }
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	my $lr = RDF::Base::Arc::List->new(\@arcs);

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    $lr = $lr->unique_arcs_prio($uap);
	}
	elsif( my $aod = $args->{arc_active_on_date} )
	{
	    $lr = $lr->arc_active_on_date($aod);
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
	    push @arcs, @{$node->{'lit_revarc_active'}};
	}

	if( $inactive )
	{
	    push @arcs, @{$node->{'lit_revarc_inactive'}};
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    return RDF::Base::Arc::List->new(\@arcs)->unique_arcs_prio($uap);
	}
	elsif( my $aod = $args->{arc_active_on_date} )
	{
	    return RDF::Base::Arc::List->new(\@arcs)->arc_active_on_date($aod);
	}
	else
	{
	    return RDF::Base::Arc::List->new(\@arcs);
	}
    }
}


##############################################################################

=head3 first_revarc

=cut

sub first_revarc
{
    return shift->revarc_list(@_)->get_first_nos;
}


##############################################################################

=head3 revarc

=cut

sub revarc
{
    return shift->lit_revarc(@_);
}


##############################################################################

=head3 vacuum

This vacuums both arcs and revarcs. Normal vacuum doesn't vacuum revarcs

=cut

sub vacuum
{
    my( $node, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $no_lim = RDF::Base::Arc::Lim->parse(['active','inactive']);
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


##############################################################################

=head3 merge_node

=cut

sub merge_node
{
    confess "merging a literal resource?!";
}


##############################################################################

=head3 link_paths

=cut

sub link_paths
{
    return [];
}


##############################################################################

=head3 wu

=cut

sub wu
{
    my( $node, $pred_name, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    return $node->first_literal($args)->wu($pred_name,$args);
}


##############################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id, if existing.

=cut

sub sysdesig  # The designation of obj, including node id
{
    my( $node ) = @_;
    my $lit = $node->first_literal;
#    cluck $lit unless ref $lit;
    if( $lit and $lit->is_literal )
    {
	if( defined $lit->plain )
	{
	    return sprintf "%s: <value> (%s)", $node->id, $lit->desig;
	}
	else
	{
	    return sprintf "%s: <value> (<undef>)", $node->id;
	}
    }
    else
    {
	return sprintf "%s: <no-value>", $node->id;
    }
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


##############################################################################

=head2 loc

  $n->loc( \%args )

Asking to translate this word.  But there is only one value.

Used by L<RDF::Base::List/loc>.

Returns: A plain string

=cut

sub loc
{
    return $_[0]->plain;
}


##############################################################################

=head2 plain

=cut

sub plain
{
#    debug "Returning resource literal plain value ".$_[0]->lit_revarc->{'value'};
#    cluck if $_[0]->lit_revarc->{'value'}->plain eq 'Avisita Arbete';
    return $_[0]->lit_revarc->{'value'}->plain;
}


##############################################################################

=head2 on_revarc_del

=cut

sub on_revarc_del
{
    my( $n, $arc, $pred_name, $args ) = @_;

    if( $arc->equals( $n->lit_revarc ) )
    {
        foreach my $oarc ( @{$n->{'lit_revarc_active'}},
                           @{$n->{'lit_revarc_inactive'}} )
        {
            delete $oarc->value_node->{'literal_arc'};
        }

        # Copy value to the new first arc
        my $val = $arc->{'value'};
        my $new_first_arc = $n->lit_revarc;
        return unless $new_first_arc->is_arc;

        # Keep new value if set
        return if $new_first_arc->{'value'};

        # Copy previous value to new arc if the new was undef

        $new_first_arc->set_value($val,
                                  {%$args,
                                   force_set_value=>1,
                                   force_set_value_same_version=>1,
                                  });
    }
}


##############################################################################

=head2 on_revarc_add

=cut

sub on_revarc_add
{
    my( $n, $arc, $pred_name, $args ) = @_;

    foreach my $oarc ( @{$n->{'lit_revarc_active'}},
                       @{$n->{'lit_revarc_inactive'}} )
    {
        delete $oarc->value_node->{'literal_arc'};
    }
}


##############################################################################


1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Literal>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
