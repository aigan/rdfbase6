package RDF::Base::Action::search_save;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use RDF::Base::Search;

=head1 DESCRIPTION

RDFbase Action for saving sessionobj search in session

=cut

sub handler
{
    my( $req ) = @_;

    my $col = $req->session->search_save();

    return "Saved search as ".$col->label;
}


1;
