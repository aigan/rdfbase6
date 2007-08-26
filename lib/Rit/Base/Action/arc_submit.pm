#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_submit;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for submitting an arc
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Rit::Base::Arc;

sub handler
{
    my( $req ) = @_;

    my $changed = 0;

    my $q = $req->q;

    my $aid = $q->param('arc_id');
    my $arc = Rit::Base::Arc->get( $aid );
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
