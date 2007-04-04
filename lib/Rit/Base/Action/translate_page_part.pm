#  $Id$  -*-cperl-*-
package Rit::Base::Action::translate_page_part;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for updating a page part resource
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

use Para::Frame::Utils qw( throw );

use Rit::Base::Resource;

sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $nid = $q->param('nid') or die "nid param missing";
    my $lc = $q->param('lc') or die "lc param missing";
    my $trt = $q->param('translation') or die "translation missing";

    my $n = Rit::Base::Resource->get_by_id( $nid );
    my $wst = Rit::Base::Resource->get_by_label('website_text');
    my $l = Rit::Base::Resource->find_one({code=>$lc, is=>'language'});
    my $tb = Rit::Base::Resource->find_one({name=>'textbox', scof=>'text'});

    unless( $n->has_value(is=>$wst) )
    {
	throw('validation', "The node must be a website_text");
    }

    my $arcs = $n->find_arcs( 'description' => {is_of_language=>$l});

    if( my $arc = $arcs->get_first_nos )
    {
	$arc->obj->update('value'=>$trt);
    }
    else
    {
	my $pred = Rit::Base::Pred->get_by_label( 'description' );
	my $props =
	{
	 is_of_language => $l,
	};

	my $value = Rit::Base::Resource->create( $props );
	Rit::Base::Arc->create({
				subj    => $value,
				pred    => 'value',
				value   => $trt,
				valtype => $pred->valtype,
			       });

	$n->add($pred => $value);
    }

    return "Översättning ändrad";
}

1;
