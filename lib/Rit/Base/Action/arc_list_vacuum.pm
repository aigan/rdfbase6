package Rit::Base::Action::arc_list_vacuum;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( debug );

use Rit::Base::Resource::Change;

=head1 DESCRIPTION

Ritbase Action for vacuuming a list of arcs

=cut

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
	my $arc = Rit::Base::Resource->get( $aid );

	$arc->vacuum( { res => $res } );
    }

    my $changes = $res->changes;

    return "$changes changes made";
}


1;
