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

use Para::Frame::L10N qw( loc );

use Rit::Base::Time qw( now );
use Rit::Base::Utils qw( parse_propargs );

sub handler
{
    my( $req ) = @_;

    throw('denied', "Nope") unless $req->session->user->level >= 20;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q = $req->q;
    my $id = $q->param('id');

    unless( $id ) # creating or editing location?
    {
	$id = $Rit::dbix->get_nextval('node_seq');
	$q->param('id', $id);

	$q->param('arc___pred_created', now->iso8601 );
    }

    my $node = Rit::Base::Resource->get($id);
    $node->update_by_query($args);

    if( $res->changes )
    {
	$node->mark_updated();
    }

    $res->autocommit;

    if( $res->changes )
    {
	return loc("Changes saved");
    }
    else
    {
	return loc("No changes");
    }
}


1;
