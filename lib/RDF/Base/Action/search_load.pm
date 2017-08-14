package RDF::Base::Action::search_load;
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

use Para::Frame::Utils qw( debug throw );

use RDF::Base::Search;

=head1 DESCRIPTION

RDFbase Action for loading sessionobj search from session

=cut

sub handler
{
    my( $req ) = @_;

    my( $label ) = $req->q->param('label');
    unless( $label )
    {
        throw('validation', 'No label given');
    }

    my $col = $req->session->search_load($label);

    return "Loaded search ".$col->label;
}


1;
