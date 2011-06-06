package Rit::Base::Action::translate_html;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

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
    my $predname = $q->param('pred') or die "pred missing";


    my $n = Rit::Base::Resource->get_by_id( $nid );
    my $l = Rit::Base::Resource->find_one({code=>$lc, is=>$C_language}, $args);

    $n->session_history_add('updated');

    debug "  Translating ".$n->sysdesig." ".$predname;
    debug "  Looking up arc with the language ".$l->sysdesig;
    my $arcs = $n->arc_list($predname, {'obj.is_of_language'=>$l}, $args);

#    return "  Found arc: ".$arcs->sysdesig;

    if( my $arc = $arcs->get_first_nos )
    {
#	debug "  updating existing arc";
	$arc->set_value($trt, $args);
    }
    else
    {
#	debug "  Adding description to $n->{id}";
	$arc = $n->add_arc({$predname => $trt}, $args);
#	debug "Added arc $arc->{id}";
	$arc->value->add({is_of_language => $l}, $args);
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
