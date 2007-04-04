#  $Id$  -*-cperl-*-
package Rit::Base::Action::node_search;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for searching nodes
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw trim );

use Rit::Base::Search;

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection;
    $search_col->reset;

    my $query = $req->q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );
    length $query or throw('incomplete', "Nått får du väl skriva ändå va?");

    my $props = {};

    foreach my $row (split /\r?\n/, $query )
    {
	trim(\$row);
	next unless length $row;

	my( $key, $value ) = split(/\s+/, $row, 2);
	$props->{$key} = $value;
    }

    my $search = Rit::Base::Search->new();
    $search->modify($props);
    $search->execute;
    $search_col->add($search);


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
