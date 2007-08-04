#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_list_vacuum;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for vacuuming a list of arcs
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( debug );

use Rit::Base::Utils qw( getnode );
use Rit::Base::Resource::Change;


sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $res = Rit::Base::Resource::Change->new;

    foreach my $param ( $q->param )
    {
#	my $value = $q->param($param);
	next unless $param =~ /^arc_(\d+)$/;
	my $aid = $1;

	debug "Vacuum arc $aid";
	my $arc = getnode( $aid );

	$arc->vacuum( { res => $res } );
    }

    my $changes = $res->changes;

    return "$changes changes made";
}


1;
