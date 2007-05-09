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

use Para::Frame::Utils qw( );

use Rit::Base::Utils qw( getarc getnode getpred );

sub handler
{
    my( $req ) = @_;

    my $changed = 0;

    my $q = $req->q;

    my $aid = $q->param('arc_id');
    my $arc = getnode( $aid );
    my $desig = $arc->sysdesig;

    if( $arc->submit )
    {
	return "Submitted arc $desig";
    }
}


1;
