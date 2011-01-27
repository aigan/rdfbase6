package Rit::Base::Action::search_modify;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

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
