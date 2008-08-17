#  $Id$  -*-cperl-*-
package Rit::Base::Action::search_transform;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================
use strict;

use Rit::Base::Search;

use Para::Frame::Utils qw( debug datadump );

use Rit::Base::Utils qw( query_desig );

=head1 DESCRIPTION

Ritbase Action for transforming one searchlist to antother

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my $lookup = $req->q->param('transform')
      or die "No transform given";

    my $l = $search_col->result;

    debug "Transforming list to $lookup";

    my $l2 = $l->transform($lookup);

#    debug datadump( $l2->{'search'}{'custom_result'}, 2 );

    $search_col->reset->set_result( $l2 );


    return "";
}


1;
