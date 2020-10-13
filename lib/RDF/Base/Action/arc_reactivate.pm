package RDF::Base::Action::arc_reactivate;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
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

use RDF::Base::Utils qw( );
use RDF::Base::Resource;

=head1 DESCRIPTION

RDFbase Action for activating an arc

=cut

sub handler
{
	my( $req ) = @_;
	$req->require_cm_access;

	my $changed = 0;

	my $q = $req->q;

	# ignored...
	$q->delete('val');
	$q->delete('pred');
	$q->delete('literal_arcs');

	my $aid = $q->param('arc_id');
	my $arc = RDF::Base::Resource->get( $aid );
	my $desig = $arc->sysdesig;

	my $res = RDF::Base::Resource::Change->new;
	my $args = { res => $res };

	$arc->subj->session_history_add('updated');

	if( $arc->reactivate($args) )
	{
		return "Re-activated arc";
	}
}


1;
