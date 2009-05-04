package Rit::Base::Action::search_execute;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Time::HiRes qw( time );

use Para::Frame::Utils qw( debug );

use Rit::Base::Search;

=head1 DESCRIPTION

Ritbase Action for running sessionobj search

=cut

sub handler
{
    my( $req ) = @_;

    my $search_col = $req->session->search_collection or die "No search obj";
    $search_col->reset_result;

    if( $req->user->level < 20 )
    {
	# Store search stats
	$search_col->add_stats(1);
    }

#    $search_col->order_default(['score desc', 'random()']);

    my $time = time;
    $search_col->execute;
    my $took = time - $time;
    debug sprintf("Execute: %2.2f\n", $took);


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
