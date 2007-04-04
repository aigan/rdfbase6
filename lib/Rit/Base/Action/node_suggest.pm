#  $Id$  -*-cperl-*-
package Rit::Base::Action::node_suggest;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action ... should be in RG
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

use Rit::Base::Utils qw( cache_sync );
use Rit::Base::Time qw( now );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $class_id = $q->param('scof') or die;
    my $name     = $q->param('name') or die;
    my $comment  = $q->param('customer_comment');

    my $id = $Rit::dbix->get_nextval('node_seq');
    my $node = Rit::Base::Resource->get($id);

    $node->add({
	created  => now,
	inactive => 1,
	scof     => $class_id,
	name     => $name,
	customer_comment => $comment,
    });

    $q->param('prop_is', $id );

    $q->param('step_add_params', 'prop_is');

    return "Förslag mottaget";
}


1;
