package RDF::Base::Action::search_filter;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use RDF::Base::Search;

use Para::Frame::Utils qw( debug datadump );

use RDF::Base::Utils qw( query_desig parse_query_props );

=head1 DESCRIPTION

RDFbase Action for transforming one searchlist to antother

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

    if( my $box = $q->param('filter') )
    {
        my $bprops = parse_query_props($box);
#        debug( query_desig( $bprops ) );
        foreach my $key (keys %$bprops )
        {
            $params->{$key} = $bprops->{$key};
        }
    }


    my $l = $search_col->result;

    debug "Filtering list with ".query_desig($params);

    my $l2 = $l->find($params);

    debug "Filtered";

    $search_col->reset->set_result( $l2 );

    return "";
}


1;
