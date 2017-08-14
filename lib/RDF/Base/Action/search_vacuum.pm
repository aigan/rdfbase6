package RDF::Base::Action::search_vacuum;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2013-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use RDF::Base::Search;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );
use Para::Frame::L10N qw( loc );

use RDF::Base::Utils qw( query_desig parse_propargs solid_propargs );

=head1 DESCRIPTION

RDFbase Action for transforming one searchlist to antother

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my( $args_in ) = solid_propargs({
                                  activate_new_arcs => 1,
                                  no_notification => 1,
                                 });

    my $l_in = $search_col->result;
		my $l = $l_in->new([$l_in->as_array]); # Ensure its not modified by others

    $req->add_background_job( 'background_vacuum',
                              \&do_next, $l, $l->get_first_nos, $args_in );

    sub do_next
    {
        my( $req, $l, $n, $args ) = @_;

        debug sprintf "Vacuum % 5d of % 5d: %s", $l->count, $l->size, $n->sysdesig;

        $n->vacuum_node( $args );

        if( $l->last )
        {
            debug "Vacuum DONE";
        }
        else
        {
            $req->add_background_job( 'background_vacuum',
                                      \&do_next, $l, $l->get_next_nos, $args );
        }
    }


    return("Doing vacuum in background");
}


1;
