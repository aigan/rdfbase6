#  $Id$  -*-cperl-*-
package Rit::Guides::Action::translate_page_part;

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

    my $arcs = $n->find_arcs( 'description' => {language=>$l});

    if( my $arc = $arcs->first )
    {
	$arc->obj->update('value'=>$trt);
    }
    else
    {
	my $pred = Rit::Base::Pred->get_by_label( 'description' );
	my $props =
	{
	 language => $l,
	 value => $trt,
	 datatype => $pred->valtype,
	};

	my $value = Rit::Base::Resource->create( $props );

	$n->add($pred => $value);
    }

    return "Översättning ändrad";
}

1;
