#  $Id$  -*-cperl-*-
package Rit::Guides::Action::search_modify;
use strict;

use Rit::Base::Search;

sub handler
{
    my( $req ) = @_;

    my $search = $req->session->search or die "No search obj";

    $search->modify_from_query;

    return "";
}


1;
