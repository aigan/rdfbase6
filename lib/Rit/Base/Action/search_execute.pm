#  $Id$  -*-cperl-*-
package Rit::Guides::Action::search_execute;

use strict;
use Time::HiRes qw( time );

use Para::Frame::Utils qw( debug );

use Rit::Base::Search;

sub handler
{
    my( $req ) = @_;

    my $search = $req->session->search or die "No search obj";

    if( $req->user->level < 20 )
    {
	# Store search stats
	$search->add_stats(1);
    }

    $search->order_default(['score desc', 'random()']);


    my $time = time;
    $search->execute;
    my $took = time - $time;
    debug sprintf("Execute: %2.2f\n", $took);


    if( my $result_url = $req->q->param('search_result') )
    {
	$search->result_url( $result_url );
    }

    if( my $form_url = $req->q->param('search_form') )
    {
	$search->form_url( $form_url );
    }

    return "";
}


1;
