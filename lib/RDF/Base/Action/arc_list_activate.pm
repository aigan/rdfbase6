package RDF::Base::Action::arc_list_activate;
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
use RDF::Base::Utils qw( arc_lock arc_unlock );

=head1 DESCRIPTION

RDFbase Action for activating a list of arcs

=cut

sub handler
{
    my( $req ) = @_;
    $req->require_cm_access;

    my $q = $req->q;
    my $cnt = 0;

    my $res = RDF::Base::Resource::Change->new;
    my $args = { res => $res };

    my @arc_id_list;
    foreach my $param ( $q->param )
    {
#	my $value = $q->param($param);
        next unless $param =~ /^arc_(\d+)$/;
        push @arc_id_list, $1;
    }

    arc_lock();
    my $cnt = 0;

    foreach my $aid ( sort @arc_id_list )
    {
        $Para::Frame::REQ->may_yield unless ++ $cnt % 100;

        debug "Handling arc $aid";
        my $arc = RDF::Base::Resource->get( $aid );

        next unless $arc->is_arc;

        if ( $arc->is_new )
        {
            $arc->submit($args);
        }

        if ( $arc->submitted )  # May have changed during process
        {
            if ( $arc->activate($args) )
            {
                $cnt ++;
            }
        }
    }

    arc_unlock();

    $res->autocommit;

    return "Activated $cnt arcs";
}


1;
