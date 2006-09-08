#  $Id$  -*-cperl-*-
package Rit::Guides::Action::translate_page_create;

use strict;

use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Rit::Base::Resource;
use Rit::Base::Constants qw( $C_webpage );

sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $page_base = $q->param('page_path_base') or die "page base missing";

    if( $page_base =~ /\./ )
    {
	throw('validation', "Malformed page base");
    }

    my $props =
    {
     is => $C_webpage,
     code => $page_base,
    };

    my $n = Rit::Base::Resource->create( $props );

    $q->param('id' => $n->id );

    return "Textdel skapad";
}

1;
