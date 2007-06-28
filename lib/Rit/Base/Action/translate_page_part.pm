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
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;

use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Rit::Base::Resource;
use Rit::Base::Constants qw( $C_website_text $C_language );
use Rit::Base::Utils qw(parse_propargs);

sub handler
{
    my ($req) = @_;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q = $req->q;

    my $nid = $q->param('nid') or die "nid param missing";
    my $lc = $q->param('lc') or die "lc param missing";
    my $trt = $q->param('translation') or die "translation missing";

    my $n = Rit::Base::Resource->get_by_id( $nid );
    my $l = Rit::Base::Resource->find_one({code=>$lc, is=>$C_language}, $args);
    my $tb = Rit::Base::Resource->find_one({name=>'textbox', scof=>'text'}, $args);

    unless( $n->has_value({is=>$C_website_text}, $args) )
    {
	throw('validation', "The node must be a website_text");
    }

    my $arcs = $n->find_arcs({ 'description' => {is_of_language=>$l} }, $args);

    if( my $arc = $arcs->get_first_nos )
    {
	$arc->obj->update({'value'=>$trt}, $args);
    }
    else
    {
	my $pred = Rit::Base::Pred->get_by_label( 'description', $args );
	my $props =
	{
	 is_of_language => $l,
	};

	my $value = Rit::Base::Resource->create( $props, $args );
	Rit::Base::Arc->create({
				subj    => $value,
				pred    => 'value',
				value   => $trt,
				valtype => $pred->valtype,
			       }, $args);

	$n->add({$pred => $value}, $args);
    }

    $res->autocommit;

    if( $res->changes )
    {
	return loc("Translation changed");
    }
    else
    {
	return loc("No changes");
    }
}

1;
