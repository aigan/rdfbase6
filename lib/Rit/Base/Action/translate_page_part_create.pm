#  $Id$  -*-cperl-*-
package Rit::Base::Action::translate_page_part_create;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw );
use Para::Frame::L10N qw( loc );

use Rit::Base::Resource;
use Rit::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

Ritbase Action for adding a page part resource

=cut

sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $code = $q->param('pp_code') or die "code missing";

    unless( $code =~ /^\/.+\@\w+/ )
    {
	throw('validation', "Malformed code");
    }


    my $wst = Rit::Base::Resource->get_by_anything('website_text');
    my $pred = Rit::Base::Pred->get_by_anything( 'description' );

    my $props =
    {
     is => $wst,
     code => $code,
    };

    my( $args, $arclim, $res ) = parse_propargs('auto');
    my $n = Rit::Base::Resource->create( $props, $args );
    $n->session_history_add('updated');

    $q->param('id' => $n->id );

    $res->autocommit;

    if( $res->changes )
    {
	return loc("Pagepart created");
    }
    else
    {
	return loc("No changes");
    }
}

1;
