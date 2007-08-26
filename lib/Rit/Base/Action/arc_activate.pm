#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_activate;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for activating an arc
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Rit::Base::Utils qw( );
use Rit::Base::Resource;

sub handler
{
    my( $req ) = @_;

    my $changed = 0;

    my $q = $req->q;

    # ignored...
    $q->delete('val');
    $q->delete('pred');
    $q->delete('literal_arcs');

    my $aid = $q->param('arc_id');
    my $arc = Rit::Base::Resource->get( $aid );
    my $desig = $arc->sysdesig;

    $arc->subj->session_history_add('updated');

    if( $arc->activate )
    {
	return "Activated arc";
    }
}


1;
