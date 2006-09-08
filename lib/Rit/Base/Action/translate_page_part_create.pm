#  $Id$  -*-cperl-*-
package Rit::Guides::Action::translate_page_part_create;

use strict;

use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Rit::Base::Resource;

sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $code = $q->param('pp_code') or die "code missing";

    unless( $code =~ /^\/.+\@\w+/ )
    {
	throw('validation', "Malformed code");
    }


    my $wst = Rit::Base::Resource->get_by_label('website_text');
    my $pred = Rit::Base::Pred->get_by_label( 'description' );

    my $props =
    {
     is => $wst,
     code => $code,
    };

    my $n = Rit::Base::Resource->create( $props );

    $q->param('id' => $n->id );

    return "Textdel skapad";
}

1;
