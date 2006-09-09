#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_clear;
use strict;

use Rit::Base::Search;

sub handler
{
    my( $req ) = @_;

    my $search = $req->session->search;
    $search->reset;

    if( my $form_url = $req->q->param('search_form') )
    {
	$search->form_url( $form_url );
    }
    else
    {
	$search->form_url( $req->referer );
    }

    return "";
}


1;
