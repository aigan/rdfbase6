#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_clear;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for clearing sessionobj search
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================
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
