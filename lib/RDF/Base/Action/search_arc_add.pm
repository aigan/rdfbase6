package RDF::Base::Action::search_arc_add;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2015-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump throw );
use Para::Frame::L10N qw( loc );
use Para::Frame::Widget qw( confirm_simple );

use RDF::Base::Search;
use RDF::Base::Utils qw( query_desig parse_arc_add_box parse_propargs );
use RDF::Base::Literal::Time qw( now );

=head1 DESCRIPTION

RDFbase Action for adding arcs to all nodes of the search result

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my $l = $search_col->result;

    if( $l->size > 10000 )
    {
        throw 'validation', "Not modifying more than 1000 nodes";
    }

    my $q = $req->q;
    my $query = $q->param('query');

    # Removes both new, submitted and active
    my( $args, $arclim, $res ) = parse_propargs( 'auto' );

    my $timestamp = now();
    $args->{created} = $timestamp;
    $args->{updated} = $timestamp;

    my $props = parse_arc_add_box( $query, $args );


    confirm_simple(sprintf "Adding arcs to %d nodes?", $l->size );

    $l->reset;                  # if used before...
    eval
    {
        while ( my $n = $l->get_next_nos )
        {
            unless( $l->count % 10 )
            {
                unless( $l->count % 100 )
                {
                    $req->note(sprintf "Modified % 5d of % 5d", $l->count, $l->size);
                }
                die "cancelled" if $req->cancelled;
                $req->may_yield;
            }

            $n->add( $props, $args );

            $res->autocommit($args);
        }
    };


    die $@ if $@;

    if ( $res->changes )
    {
        return sprintf "Added %d arcs over %d nodes", $res->changes, $l->count;
    }
    else
    {
        return loc("No changes");
    }
}


1;
