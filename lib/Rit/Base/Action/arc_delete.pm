package Rit::Base::Action::arc_delete;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2010 Avisita AB.  All Rights Reserved.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( );
use Rit::Base::Resource::Change;

sub handler
{
    my( $req ) = @_;
    $req->require_root_access;

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

    my $args = { res => $res };
    if( $q->param('force') )
    {
	$args->{'force'} = 1;
    }

    my $cnt = 0;
    foreach my $arc ( @arcs )
    {
	$arc->remove( $args );

	unless( ++$cnt % 100 )
	{
	    $req->note(sprintf "Removed %6d of %6d", $cnt, $#arcs);
	    $req->may_yield;
	    die "cancelled" if $req->cancelled;
	}
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
