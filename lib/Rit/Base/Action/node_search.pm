package Rit::Base::Action::node_search;
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

use Para::Frame::Utils qw( throw trim debug datadump );

use Rit::Base::Utils qw( query_desig parse_query_props );
use Rit::Base::Search;

=head1 DESCRIPTION

Ritbase Action for searching nodes

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection;
    $search_col->reset;

    my $query = $req->q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );
    length $query or throw('incomplete', "Query empty");

    my $props = parse_query_props( $query );

    my $args = {};
    if( my $arclim_in = delete $props->{'arclim'} )
    {
	unless( $arclim_in =~ /^[\[\'\]\_a-z,]+$/ )
	{
	    throw('validation', "arclim format invalid");
	}

	$args->{'arclim'} = eval $arclim_in;
    }

# Faster to not order result
#    unless( $props->{'order_by'} )
#    {
#	$props->{'order_by'} = 'desig';
#    }


    my $search = Rit::Base::Search->new($args);
    debug "Searching with:\n".query_desig($props);
    $search->modify($props, $args);
    $search->execute($args);
    $search_col->add($search);

#    debug "Search_col now contains";
#    debug datadump($search_col,2);


    if( my $result_url = $req->q->param('search_result') )
    {
	$search_col->result_url( $result_url );
    }

    if( my $form_url = $req->q->param('search_form') )
    {
	$search_col->form_url( $form_url );
    }

    return "";
}


1;
