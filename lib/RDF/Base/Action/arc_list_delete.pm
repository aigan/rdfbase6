package RDF::Base::Action::arc_list_delete;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( debug );

use RDF::Base::Resource::Change;

=head1 DESCRIPTION

RDFbase Action for removing arcs

=cut

sub handler
{
    my( $req ) = @_;
    $req->require_root_access;

    my $q = $req->q;

    # Remove arcs in reverese id order

    my @arc_id_list;
    foreach my $param ( $q->param )
    {
        next unless $param =~ /^arc_(\d+)$/;
        push @arc_id_list, $1;
    }

    my $res = RDF::Base::Resource::Change->new;

    foreach my $arc_id ( reverse sort @arc_id_list )
    {
        my $arc = RDF::Base::Resource->get( $arc_id );
        if ( $arc->is_arc )
        {
            $arc->remove( { res => $res } );
        }
    }

    $res->autocommit;

    if ( my $cnt = $res->changes )
    {
        return "Deleted $cnt arcs";
    }
    else
    {
        return "No change";
    }
}


1;
