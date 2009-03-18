package Rit::Base::Action::arc_unsubmit;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use 5.010;
use strict;
use warnings;

use Rit::Base::Arc;

=head1 DESCRIPTION

Ritbase Action for unsubmitting an arc

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

    if( $arc->unsubmit )
    {
	return "Unsubmitted arc";
    }
}


1;
