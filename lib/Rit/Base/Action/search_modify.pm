#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_modify;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================
use strict;

use Rit::Base::Search;

=head1 DESCRIPTION

Ritbase Action for modifying sessionobj search

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    $search_col->first_rb_part->modify_from_query;

    return "";
}


1;
