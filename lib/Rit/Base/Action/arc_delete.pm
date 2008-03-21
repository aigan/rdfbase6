#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_delete;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( );
use Rit::Base::Resource::Change;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $node_id = $q->param('id');
    my $node = Rit::Base::Resource->get( $node_id );
    my $desig = $node->sysdesig;
    my $res = Rit::Base::Resource::Change->new;

    my @arc_ids = $q->param('arc_delete');
    my( @arcs );
    foreach my $arc_id (@arc_ids)
    {
	my $arc = Rit::Base::Arc->get( $arc_id ) or die "Can't find arc";
	push @arcs, $arc;
    }

    foreach my $arc ( @arcs )
    {
	$arc->remove( { res => $res } );
    }

    $res->autocommit;

    if( $res->changes )
    {
	return "Deleted node $desig";
    }
    else
    {
	return "No change";
    }
}


1;
