#  $Id$  -*-cperl-*-
package Rit::Base::Action::node_update;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for editing nodes
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;
use Data::Dumper;

use Rit::Base::Time qw( now );

sub handler
{
    my( $req ) = @_;

    throw('denied', "Nope") unless $req->session->user->level >= 20;

    my $q = $req->q;
    my $id = $q->param('id');

    unless( $id ) # creating or editing location?
    {
	$id = $Rit::dbix->get_nextval('node_seq');
	$q->param('id', $id);

	$q->param('arc___pred_created', now->iso8601 );
    }

    my $node = Rit::Base::Resource->get($id);
    $node->update_by_query();
    if( $req->user->level >= 20 )
    {
	$node->update_adr_by_query();
    }

    return "Resource updated";
}


1;
