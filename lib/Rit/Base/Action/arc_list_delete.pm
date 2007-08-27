#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_list_delete;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for removing arcs
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

use Rit::Base::Resource::Change;


sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    # Remove arcs in reverese id order

    my @arc_id_list;
    foreach my $param ( $q->param )
    {
	next unless $param =~ /^arc_(\d+)$/;
	push @arc_id_list, $1;
    }

    my $res = Rit::Base::Resource::Change->new;

    foreach my $arc_id ( reverse sort @arc_id_list )
    {
	Rit::Base::Arc->get($arc_id)->remove( { res => $res } );
    }

    $res->autocommit;

    if( my $cnt = $res->changes )
    {
	return "Deleted $cnt arcs";
    }
    else
    {
	return "No change";
    }
}


1;
