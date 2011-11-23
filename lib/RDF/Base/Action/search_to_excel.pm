package RDF::Base::Action::search_to_excel;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( debug datadump catch throw );

use RDF::Base::Renderer::Search_to_Excel;


sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $search_col = $req->session->search_collection or die "No search obj";

#    $search_col->reset_result;
    unless( $search_col->is_active )
    {
#	my $maxlim = RDF::Base::Search::TOPLIMIT;
#	debug "Setting maxlim to $maxlim";
#	$search_col->first_rb_part->{'maxlimit'} = $maxlim;
	$search_col->execute;
    }


    ### Setting up file response object

    my $home = $req->site->home;
    my $id = $req->id;
    my $resp_path = $home->url_path . "/generated/result-$id.xls";

    my $args = {};
#    $args->{'req'}  = $req;
    $args->{'url'}  = $resp_path;
#    $args->{'site'} = $req->site;
    $args->{'renderer'} = RDF::Base::Renderer::Search_to_Excel->new();
#    my $file_resp = Para::Frame::Request::Response->new($args);
    my $file_resp = $req->response->clone($args);
    unless( $file_resp->render_output )
    {
	if( my $err = catch($@) )
	{
	    $req->result->error('action', $@);
	}

	throw('action', "Export failed");
    }

    my $file_url = $file_resp->page->page_url_path_with_query_and_reqnum;
    $req->session->register_result_page($file_resp, $file_url);
    $q->param('file_download_url', $file_url);

    return "List exported to excel file ".$file_resp->page->name;
}


1;
