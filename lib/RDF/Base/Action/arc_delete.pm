package RDF::Base::Action::arc_delete;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( trim );

use RDF::Base::Utils qw( );
use RDF::Base::Resource::Change;

sub handler
{
    my( $req ) = @_;
    $req->require_root_access;

    my $q = $req->q;

    my $node_id = $q->param('id');
    my $node = RDF::Base::Resource->get( $node_id );
    my $desig = $node->sysdesig;
    my $res = RDF::Base::Resource::Change->new;

    my @arc_ids = $q->param('arc_delete');
    my( @arcs );
    foreach my $arc_id (@arc_ids)
    {
	my $arc = RDF::Base::Arc->get( $arc_id ) or die "Can't find arc";
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
