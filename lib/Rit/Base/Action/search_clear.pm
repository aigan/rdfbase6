package Rit::Base::Action::search_clear;
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

use Rit::Base::Search;

=head1 DESCRIPTION

Ritbase Action for clearing sessionobj search

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection;
    $search_col->reset;

    my $q = $req->q;

    if( my $form_url = $req->q->param('search_form') )
    {
	$search_col->form_url( $form_url );
    }
#    else
#    {
#	$search_col->form_url( $req->referer_path );
#    }

    if( my $result_url = $req->q->param('search_result') )
    {
	$search_col->result_url( $result_url );
    }



    return "";
}


1;
