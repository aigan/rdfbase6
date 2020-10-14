package RDF::Base::Action::rollback_removal;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2020 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

#use Para::Frame::L10N qw( loc );
use Para::Frame::Utils qw( throw debug catch );

use RDF::Base::Literal::Time qw( date now );
use RDF::Base::Utils qw( parse_propargs arc_lock arc_unlock solid_propargs );

=head1 DESCRIPTION

RDFbase Action for rollback deletes.

=cut

sub handler
{
	my( $req ) = @_;
	$req->require_cm_access;

	my( $args, $arclim, $res ) =
		solid_propargs({
										activate_new_arcs => 1,
										no_notification => 1,
										postpone_check => 1,
									 });
	$args->{'updated'} = now();

	my $q = $req->q;

	my $arc_id = $q->param('arc_id');
	unless( $arc_id )
	{
		throw('incomplete', "arc_id missing");
	}
	my $node = RDF::Base::Resource->get($arc_id);
	my $stamp = $node->deactivated;
	if( !$stamp )
	{
		return "Not a removal: ".$node->sysdesig;
	}

	$req->result_message("Restore removal " .$stamp );

	my $arcrecs = $RDF::dbix->select_list("from arc where deactivated=? and active is false and valtype = 0", $stamp);

	$req->result_message("Restore from ". $arcrecs->size ." arcs." );

	arc_lock();

	my %nodes;
	my %isarcs;
	my $cnt = 0;
	foreach my $arcrec ( $arcrecs->as_array ){
		$cnt++;
		my $arc = RDF::Base::Arc->get_by_rec( $arcrec );
		### Only processing REMOVAL arcs
		next if !$arc->is_removal;

		my $arc_prev = $arc->replaces;
		if( !$arc_prev )
		{
			debug "Previous version not found ".$arc->sysdesig;
			next;
		}

		if( $arc_prev->pred->id == 1 ){
			$isarcs{ $arc_prev->id } = $arc_prev;
			$nodes{ $arc->subj->id } = $arc->subj;
		}

		my $arc_active = $arc->active_version;
		if( $arc_active )
		{
			debug "Skipping active version: ".$arc_active->sysdesig;
			next;
		}

#		debug "Previous version ".$arc_prev->sysdesig;
		$arc_prev->reactivate( $args );

		unless( $cnt % 100 )
		{
			$req->note(sprintf "Reactivated %6d of %6d", $cnt, $arcrecs->size );
#			$req->may_yield;
		}
	}

	$req->note("Restore node classes");
	my $isarcs_cnt = 0;
	my $isarcs_tot = scalar(keys %isarcs );
	foreach my $arc ( values %isarcs )
	{
#		debug "nodes ".$sub->sysdesig;
		eval
		{
			$arc->vacuum_facet( $args );
		};
		if( $@ )
		{
			my $err = catch($@);
			$req->result_message("Failed to vacuum arc ".$arc->sysdesig .": ".$err->info );		}

		unless( ++ $isarcs_cnt % 100 )
		{
			$req->note(sprintf "Vacuumed isarc %6d of %6d", $isarcs_cnt, $isarcs_tot);
#			$req->may_yield;
		}

	}

	arc_unlock();

	my $nodes_cnt = 0;
	my $nodes_tot = scalar(keys %nodes );
	$req->note("Doing vacuum");
	foreach my $sub ( values %nodes )
	{
#		debug "nodes ".$sub->sysdesig;
		eval
		{
			$sub->vacuum_node( $args );
		};
		if( $@ )
		{
			my $err = catch($@);
			$req->result_message("Failed to vacuum ".$sub->sysdesig .": ".$err->info );		}

		unless( ++ $nodes_cnt % 100 )
		{
			$req->note(sprintf "Vacuumed %6d of %6d", $nodes_cnt, $nodes_tot);
#			$req->may_yield;
		}

	}

	if ( $res->changes )
	{
		return "Restored arcs";
	}
	else
	{
		return "No changes";
	}
}


1;
