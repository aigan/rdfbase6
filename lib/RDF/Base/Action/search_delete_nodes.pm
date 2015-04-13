package RDF::Base::Action::search_delete_nodes;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2015 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use RDF::Base::Search;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump throw );
use Para::Frame::L10N qw( loc );
use Para::Frame::Widget qw( confirm_simple );

use RDF::Base::Utils qw( query_desig parse_propargs );
use RDF::Base::Literal::Time qw( now );

=head1 DESCRIPTION

RDFbase Action for removing all nodes of the search result

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my $l = $search_col->result;

    if( $l->size > 10000 )
    {
        throw 'validation', "Not removing more than 1000 nodes";
    }

    confirm_simple(sprintf "Deleting %d nodes?", $l->size );

    # Removes both new, submitted and active
    my( $args, $arclim, $res ) = parse_propargs( 'auto' );

    my $timestamp = now();
    $args->{created} = $timestamp;
    $args->{updated} = $timestamp;

    my $arcs_cnt = 0;

    $l->reset;                  # if used before...
    eval
    {
        while ( my $n = $l->get_next_nos )
        {
            unless( $l->count % 10 )
            {
                unless( $l->count % 100 )
                {
                    $req->note(sprintf "Removed % 5d of % 5d", $l->count, $l->size);
                }
                die "cancelled" if $req->cancelled;
                $req->may_yield;
            }

            my $rel_arcs = $n->arc_list(undef,undef,$args);
            $arcs_cnt += $rel_arcs->size;
            while ( my $a = $rel_arcs->get_next_nos )
            {
                unless( $rel_arcs->count % 100 )
                {
                    $req->note(sprintf "Removed arc % 5d of % 5d on %d", $rel_arcs->count, $rel_arcs->size, $n->id);
                    die "cancelled" if $req->cancelled;
                    $req->may_yield;
                }

                $a->remove($args);
            }

            my $rev_arcs = $n->revarc_list(undef,undef,$args);
            $arcs_cnt += $rev_arcs->size;
            while ( my $a = $rev_arcs->get_next_nos )
            {
                unless( $rev_arcs->count % 100 )
                {
                    $req->note(sprintf "Removed revarc % 5d of % 5d on %d", $rev_arcs->count, $rev_arcs->size, $n->id);
                    die "cancelled" if $req->cancelled;
                    $req->may_yield;
                }

                $a->remove($args);
            }
            $res->autocommit($args);
        }
    };


    die $@ if $@;

    if ( $res->changes )
    {
        return sprintf "Deleted %d arcs over %d nodes", $arcs_cnt, $l->count;
    }
    else
    {
        return loc("No changes");
    }
}


1;
