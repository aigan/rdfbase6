package Rit::Base::Action::arc_list_delete;
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

use Para::Frame::Utils qw( debug );

use Rit::Base::Resource::Change;

=head1 DESCRIPTION

Ritbase Action for removing arcs

=cut

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
	my $arc = Rit::Base::Resource->get( $arc_id );
	if( $arc->is_arc )
	{
	    $arc->remove( { res => $res } );
	}
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
