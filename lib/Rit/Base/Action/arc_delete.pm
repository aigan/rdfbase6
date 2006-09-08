#  $Id$  -*-cperl-*-
package Rit::Guides::Action::arc_delete;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( getarc getnode getpred cache_sync );

sub handler
{
    my( $req ) = @_;

    my $changed = 0;

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



    foreach my $arc ( @arcs )
    {
	$arc->remove;
    }

    return "Deleted node $desig";
}


1;
