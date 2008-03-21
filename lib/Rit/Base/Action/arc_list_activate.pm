#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_list_activate;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( debug );

use Rit::Base::Resource::Change;

=head1 DESCRIPTION

Ritbase Action for activating a list of arcs

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $cnt = 0;

    my $res = Rit::Base::Resource::Change->new;
    my $args = { res => $res };

    my @arc_id_list;
    foreach my $param ( $q->param )
    {
#	my $value = $q->param($param);
	next unless $param =~ /^arc_(\d+)$/;
	push @arc_id_list, $1;
    }

    foreach my $aid ( sort @arc_id_list )
    {
	debug "Handling arc $aid";
	my $arc = Rit::Base::Resource->get( $aid );

	next unless $arc->is_arc;

	if( $arc->is_new )
	{
	    $arc->submit($args);
	}

	if( $arc->submitted ) # May have changed during process
	{
	    if( $arc->activate($args) )
	    {
		$cnt ++;
	    }
	}
    }

    $res->autocommit;

    return "Activated $cnt arcs";
}


1;
