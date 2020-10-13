package RDF::Base::Action::node_restore;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2013-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

#use Para::Frame::L10N qw( loc );
use Para::Frame::Utils qw( throw debug );

use RDF::Base::Literal::Time qw( date now );
use RDF::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

RDFbase Action for restoring nodes.

=cut

sub handler
{
	my( $req ) = @_;
	$req->require_cm_access;

	my( $args, $arclim, $res ) = parse_propargs('auto');
	$args->{'updated'} = now();

	my $q = $req->q;

	my $id = $q->param('id');
	unless( $id )
	{
		throw('incomplete', "Id missing");
	}
	my $node = RDF::Base::Resource->get($id);

	my $time = date( $q->param('time') );
	unless( $time )
	{
		throw('incomplete', "Time missing");
	}

	my $args_search = {arc_active_on_date => $time};


	$req->note(sprintf "Restoring node %s to %s", $node->sysdesig($args_search), $time->sysdesig);


	foreach my $arc ( $node->arc_list( undef, undef, $args_search )->as_array )
	{
		next if $arc->is_removal;
		$arc->reactivate($args);
	}


	foreach my $arc ( $node->revarc_list( undef, undef, $args_search )->as_array )
	{
		next if $arc->is_removal;
		$arc->reactivate($args);
	}

	if ( $res->changes )
	{
		return "Restored node";
	}
	else
	{
		return "No changes";
	}
}


1;
