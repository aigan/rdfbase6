package Rit::Base::Action::arc_submit;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Rit::Base::Arc;

=head1 DESCRIPTION

Ritbase Action for submitting an arc

=cut

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
