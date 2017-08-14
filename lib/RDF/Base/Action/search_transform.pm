package RDF::Base::Action::search_transform;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use RDF::Base::Search;

use Para::Frame::Utils qw( debug datadump );

use RDF::Base::Utils qw( query_desig );

=head1 DESCRIPTION

RDFbase Action for transforming one searchlist to antother

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my $lookup = $req->q->param('transform')
      or die "No transform given";

    my $l = $search_col->result;

    debug "Transforming list to $lookup";

    my $l2 = $l->transform($lookup);

#    debug datadump( $l2->{'search'}{'custom_result'}, 2 );


    $search_col->reset->set_result( $l2 );
    if( my $form_url = $req->q->param('search_form') )
    {
	$search_col->form_url( $form_url );
    }

    if( my $result_url = $req->q->param('search_result') )
    {
	$search_col->result_url( $result_url );
    }


    return "";
}


1;
