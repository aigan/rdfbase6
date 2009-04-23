package Rit::Base::Action::search_filter;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Rit::Base::Search;

use Para::Frame::Utils qw( debug datadump );

use Rit::Base::Utils qw( query_desig );

=head1 DESCRIPTION

Ritbase Action for transforming one searchlist to antother

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $search_col = $req->session->search_collection
      or die "No search obj";

    my $params = {};
    foreach my $key ( $q->param() )
    {
	next unless $key =~ /^prop_(.*)/;

	$params->{$1} = $q->param($key);
    }

    my $l = $search_col->result;

    debug "Filtering list with ".query_desig($params);

    my $l2 = $l->find($params, {clean=>1});

    debug query_desig( $l2 );

    $search_col->reset->set_result( $l2 );

    return "";
}


1;
