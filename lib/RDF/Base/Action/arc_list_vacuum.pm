package RDF::Base::Action::arc_list_vacuum;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Para::Frame::Utils qw( debug );

use RDF::Base::Resource::Change;

=head1 DESCRIPTION

RDFbase Action for vacuuming a list of arcs

=cut

sub handler
{
    my( $req ) = @_;
    $req->require_cm_access;

    my $q = $req->q;
    my $res = RDF::Base::Resource::Change->new;
    my $cnt = 0;

    foreach my $param ( $q->param )
    {
        $Para::Frame::REQ->may_yield unless ++ $cnt % 100;
#	my $value = $q->param($param);
        next unless $param =~ /^arc_(\d+)$/;
        my $aid = $1;

        debug "Vacuum arc $aid";
        my $arc = RDF::Base::Resource->get( $aid );

        $arc->vacuum_node( { res => $res } );
    }

    my $changes = $res->changes;

    return "$changes changes made";
}


1;
