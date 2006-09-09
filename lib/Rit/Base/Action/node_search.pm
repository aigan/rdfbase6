#  $Id$  -*-cperl-*-
package Rit::Base::Action::node_search;
use strict;

use Para::Frame::Utils qw( throw trim );

use Rit::Base::Search;

sub handler
{
    my( $req ) = @_;

    my $search = $req->session->search;

    my $query = $req->q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );
    length $query or throw('incomplete', "Nått får du väl skriva ändå va?");

    my $prop = {};

    foreach my $row (split /\r?\n/, $query )
    {
	trim(\$row);
	next unless length $row;

	my( $key, $value ) = split(/\s+/, $row, 2);
	$prop->{$key} = $value;
    }

    #######
    $search->reset;
    $search->modify( $prop );
    $search->execute;

    if( my $result_url = $req->q->param('search_result') )
    {
	$req->session->search->result_url( $result_url );
    }

    if( my $form_url = $req->q->param('search_form') )
    {
	$req->session->search->form_url( $form_url );
    }

    return "";
}


1;
