# $Id$
package Rit::Base::Action::search_to_excel;

use strict;

use Para::Frame::Utils qw( debug datadump );

use Rit::Base::Renderer::Search_to_Excel;


sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $search_col = $req->session->search_collection or die "No search obj";
    $search_col->reset_result;

    unless( $search_col->is_active )
    {
	my $maxlim = Rit::Base::Search::TOPLIMIT;
	debug "Setting maxlim to $maxlim";
	$search_col->first_rb_part->{'maxlimit'} = $maxlim;
	$search_col->execute;
    }


    ### Setting up file response object

    my $home = $req->site->home;
    my $id = $req->id;
    my $resp_path = $home->url_path . "/generated/result-$id.xls";

    my $args = {};
    $args->{'req'}  = $req;
    $args->{'url'}  = $resp_path;
    $args->{'site'} = $req->site;
    $args->{'renderer'} = Rit::Base::Renderer::Search_to_Excel->new();
    my $file_resp = Para::Frame::Request::Response->new($args);
    unless( $file_resp->render_output )
    {
	return "Export failed";
    }

    my $file_url = $file_resp->page_url_with_query_and_reqnum;
    $req->session->register_result_page($file_resp, $file_url);
    $q->param('file_download_url', $file_url);

    return "List exported to excel";
}


1;
