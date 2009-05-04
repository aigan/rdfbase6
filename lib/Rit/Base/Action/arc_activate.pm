package Rit::Base::Action::arc_activate;
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

use Rit::Base::Utils qw( );
use Rit::Base::Resource;

=head1 DESCRIPTION

Ritbase Action for activating an arc

=cut

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
