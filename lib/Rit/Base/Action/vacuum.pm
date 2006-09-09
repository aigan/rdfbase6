#  $Id$  -*-cperl-*-
package Rit::Base::Action::vacuum;

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
