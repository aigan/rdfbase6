package RDF::Base::Action::search_vacuum;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2013 Avisita AB.  All Rights Reserved.
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
use Para::Frame::Utils qw( debug datadump );
use Para::Frame::L10N qw( loc );

use RDF::Base::Utils qw( query_desig parse_propargs );

=head1 DESCRIPTION

RDFbase Action for transforming one searchlist to antother

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my $l = $search_col->result;

    my( $args, $arclim, $res ) = solid_propargs({
                                                 activate_new_arcs => 1,
                                                 no_notification => 1,
                                                });

    my $s = $req->session;
    $res->{'vacuumed'} = $s->{'vacuumed'};
    my $n; #current node

    $l->reset;                  # if used before...
    eval
    {
        while ( $n = $l->get_next_nos )
        {
            next if $res->{'vacuumed'}{$n->{'id'}};
#            debug "* ".$l->count." : ".$n->{'id'};

            unless( $l->count % 10 )
            {
                unless( $l->count % 100 )
                {
                    $req->note(sprintf "Vacuum % 5d of % 5d", $l->count, $l->size);
                }
                die "cancelled" if $req->cancelled;
                $req->may_yield;
            }

            $n->vacuum_node( $args );

            $res->autocommit;
        }
    };

    $res->{'vacuumed'}{$n->{'id'}} = 0;
    $s->{'vacuumed'} = $res->{'vacuumed'};

    die $@ if $@;

    if ( $res->changes )
    {
        return loc("Changes saved");
    }
    else
    {
        return loc("No changes");
    }
}


1;
