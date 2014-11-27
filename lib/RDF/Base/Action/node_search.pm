package RDF::Base::Action::node_search;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( throw trim debug datadump );

use RDF::Base::Utils qw( query_desig parse_query_props );
use RDF::Base::Literal::Time;
use RDF::Base::Search;

=head1 DESCRIPTION

RDFbase Action for searching nodes

=cut

sub handler
{
    my( $req ) = @_;

    my $s = $req->session;
    my $col = $s->search_collection;

    if( $col->label )
    {
        debug "Active 1 col is $col";

        $col = $col->new; # Get a new object;
        $s->search_collection( $col ); # Seitch t new object

        debug "Active 2 col is $col";
    }
    else
    {
        $col->reset;
    }

    my $query = $req->q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );
    length $query or throw('incomplete', "Query empty");

    my $props = parse_query_props( $query );

    my $args = {};
    if ( my $arclim_in = delete $props->{'arclim'} )
    {
        $args->{'arclim'} = $arclim_in;
    }

    if ( my $aod_in = delete $props->{'arc_active_on_date'} )
    {
        my $aod = RDF::Base::Literal::Time->parse( $aod_in );
        $args->{'arc_active_on_date'} = $aod;
#        debug datadump($aod,1);
    }



    my $search = RDF::Base::Search->new($args);
    debug "Searching with:\n".query_desig($props);
    $search->modify($props, $args);
    $search->execute($args);
#    debug "Search result contains";
#    debug datadump($search->{'result'},2);

    $col->add($search);
#    debug "Search_col now contains";
#    debug datadump($col,2);


    if ( my $result_url = $req->q->param('search_result') )
    {
        $col->result_url( $result_url );
    }

    if ( my $form_url = $req->q->param('search_form') )
    {
        $col->form_url( $form_url );
    }

    return "";
}


1;
