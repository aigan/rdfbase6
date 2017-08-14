package RDF::Base::Action::search_clear;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Para::Frame::Utils qw( debug datadump throw );

use RDF::Base::Search;

=head1 DESCRIPTION

RDFbase Action for clearing sessionobj search

Will instead create a new search obj if existing search obj has been
given a label. (Becaus that search has been saved)

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

    my $q = $req->q;

    if ( my $form_url = $req->q->param('search_form') )
    {
        $col->form_url( $form_url );
    }
#    else
#    {
#	$col->form_url( $req->referer_path );
#    }

    if ( my $result_url = $req->q->param('search_result') )
    {
        $col->result_url( $result_url );
    }



    return "";
}


1;
