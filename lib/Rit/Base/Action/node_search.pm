#  $Id$  -*-cperl-*-
package Rit::Base::Action::node_search;
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

use Para::Frame::Utils qw( throw trim debug datadump );

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

    my $props = {};

    foreach my $row (split /\r?\n/, $query )
    {
	trim(\$row);
	next unless length $row;

	my( $key, $value ) = split(/\s+/, $row, 2);
	$props->{$key} = $value;
    }

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
