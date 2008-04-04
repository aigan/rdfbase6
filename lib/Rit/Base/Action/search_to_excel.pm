# $Id$
package Rit::Base::Action::search_to_excel;

use strict;

use Para::Frame::Utils qw( debug datadump );

use Rit::Base::Renderer::Search_to_Excel;


sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $dir = $req->page->dir;
    my $id = $req->id;
    my $resp_path = $dir->url_path . "/result-$id.xls";
    my $args = {};
    $args->{'renderer'} = Rit::Base::Renderer::Search_to_Excel->new();
    my $resp = $req->set_response( $resp_path, $args );

    "List exported to excel.";
}


1;
