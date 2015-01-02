package RDF::Base::Action::search_delete;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::Utils qw( debug datadump throw );

use RDF::Base::Search;

=head1 DESCRIPTION

RDFbase Action for deleting sessionobj search from session

=cut

sub handler
{
    my( $req ) = @_;

    my $s = $req->session;
    my $q = $req->q;
    my $label = $q->param('label') || '';

    if( my $col = $s->search_delete($label) )
    {
        return "Deleted search ".($col->label||'');
    }
    else
    {
        return "No change";
    }
}


1;
