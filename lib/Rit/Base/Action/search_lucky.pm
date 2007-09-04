#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_lucky;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for redirecting to form of hit, if single hit
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use URI::QueryParam;

use Para::Frame::Utils qw( debug );

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection or die "No search obj";

    my $res = $search_col->result;

    unless( $res->size == 1 )
    {
	return "";
    }

    my $node = $res->get_first_nos;

    if( my $url = $node->form_url )
    {
	my $id = $url->query_param( 'id' );
	$req->q->param('id' => $id );
	$req->set_page( $url->path_query );
	return "Redirected to the only search result";
    }

    return "";
}


1;
