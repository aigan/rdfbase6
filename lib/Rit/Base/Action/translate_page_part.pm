package Rit::Base::Action::translate_page_part;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use 5.010;
use strict;
use warnings;

use Carp qw( confess );

use Para::Frame::Utils qw( throw debug );
use Para::Frame::L10N qw( loc );

use Rit::Base::Resource;
use Rit::Base::Constants qw( $C_website_text $C_language $C_webpage );
use Rit::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

Ritbase Action for updating a page part resource

=cut

sub handler
{
    my ($req) = @_;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q = $req->q;

    my $nid = $q->param('id') or die "nid param missing";
    my $lc = $q->param('lc') or die "lc param missing";
    my $trt = $q->param('translation') or die "translation missing";

    my $n = Rit::Base::Resource->get_by_id( $nid );
    my $l = Rit::Base::Resource->find_one({code=>$lc, is=>$C_language}, $args);
    my $tb = Rit::Base::Resource->find_one({name=>'textbox', scof=>'text'}, $args);
    $n->session_history_add('updated');

    unless( $n->has_value({is=>$C_website_text}, $args) )
    {
	throw('validation', "The node must be a website_text");
    }

    debug "  Translating pagepart ".$n->sysdesig;
    debug "  Looking up arc with the language ".$l->sysdesig;
    my $arcs = $n->arc_list('has_html_content' => {'obj.is_of_language'=>$l}, $args);

#    return "  Found arc: ".$arcs->sysdesig;

    if( my $arc = $arcs->get_first_nos )
    {
#	debug "  updating existing arc";
	$arc->set_value($trt, $args);
    }
    else
    {
#	debug "  Adding description to $n->{id}";
	$arc = $n->add_arc({'has_html_content' => $trt}, $args);
#	debug "Added arc $arc->{id}";
	$arc->value->add({is_of_language => $l}, $args);
    }


    my $code = $n->first_prop('code')->plain;
    unless( $code )
    {
	confess "Code missing for ".$n->sysdesig;
    }


    #### REPAIR on demand
    #
    my $pagen = $n;
    if( $code =~ /^([^\@]+)\@(.*)$/ )
    {
	my $pagecode = $1;
	my $partcode = $2;

	unless( $pagen = $n->first_revprop('has_member') )
	{
	    $pagen = Rit::Base::Resource->
	      set_one({code => $pagecode,
		       is => $C_webpage}, $args);

	    $pagen->add({ has_member => $n }, $args );
	}
    }
    elsif( not $pagen->has_value({is => $C_webpage }) )
    {
	$pagen->add({ is => $C_webpage }, $args );
    }

    $res->autocommit;


#    $pagen->publish;

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
