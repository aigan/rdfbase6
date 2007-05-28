#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_delete;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for removing arcs
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( getarc getnode getpred cache_sync );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $node_id = $q->param('id');
    my $node = getnode( $node_id );
    my $desig = $node->sysdesig;


    my @arc_ids = $q->param('arc_delete');


    # Remove value arcs before the corresponding datatype arc
    my( @arcs, $value_arc );
    my $pred_value_id = getpred('value')->id;
    foreach my $arc_id (@arc_ids)
    {
	my $arc = getarc( $arc_id ) or die "Can't find arc";
	if( $arc->pred->id == $pred_value_id )
	{
	    $value_arc = $arc;
	}
	else
	{
	    push @arcs, $arc;
	}
    }

    # Place it first
    unshift @arcs, $value_arc if $value_arc;

    my $res = Rit::Base::Resource::Change->new;

    foreach my $arc ( @arcs )
    {
	$arc->remove( $res );
    }

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
