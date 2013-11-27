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

    my( $args, $arclim, $res ) = parse_propargs( 'solid' );

    $l->reset; # if used before...
    while( my $n = $l->get_next_nos )
    {
	unless( $l->count % 10 )
	{
            unless( $l->count % 100 )
            {
                $req->note(sprintf "Vacuum % 5d of % 5d", $l->count, $l->size);
            }
            die "cancelled" if $req->cancelled;
            $res->autocommit;
            $req->may_yield;
        }

        $n->vacuum_node( $args );
    }

    if( $res->changes )
    {
	return loc("Changes saved");
    }
    else
    {
	return loc("No changes");
    }
}


1;
