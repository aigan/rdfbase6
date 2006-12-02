#  $Id$  -*-cperl-*-
package Rit::Base::Action::vacuum;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for repairing a resource
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

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $id = $q->param('id');

    my $node = Rit::Base::Resource->get( $id );
    $node->vacuum;

    return "Resource vacuumed";
}


1;
