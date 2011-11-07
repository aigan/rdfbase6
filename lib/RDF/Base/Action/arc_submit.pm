package RDF::Base::Action::arc_submit;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use RDF::Base::Arc;

=head1 DESCRIPTION

RDFbase Action for submitting an arc

=cut

sub handler
{
    my( $req ) = @_;
    $req->require_root_access;

    my $changed = 0;

    my $q = $req->q;

    my $aid = $q->param('arc_id');
    my $arc = RDF::Base::Arc->get( $aid );
    my $desig = $arc->sysdesig;


    # ignored...
    $q->delete('val');
    $q->delete('pred');
    $q->delete('literal_arcs');

    $arc->subj->session_history_add('updated');

    if( $arc->old )
    {
	if( my $new = $arc->resubmit )
	{
	    $q->param('arc_id' => $new->id );
	    return "Resubmitted arc";
	}
    }
    elsif( $arc->submit )
    {
	return "Submitted arc";
    }
}


1;
