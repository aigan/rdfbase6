#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_modify;
use strict;

use Rit::Base::Search;

sub handler
{
    my( $req ) = @_;

    my $search = $req->session->search or die "No search obj";

    $search->first_rb_part->modify_from_query;

    return "";
}


1;
