#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_modify;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for modifying sessionobj search
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

    my $search_col = $req->session->search_collection
      or die "No search obj";

    $search_col->first_rb_part->modify_from_query;

    return "";
}


1;
