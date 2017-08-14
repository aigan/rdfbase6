package RDF::Base::Action::translate_page_part;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Carp qw( confess );

use Para::Frame::Utils qw( throw debug );
use Para::Frame::L10N qw( loc );

use RDF::Base::Resource;
use RDF::Base::Constants qw( $C_website_text $C_language $C_webpage );
use RDF::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

RDFbase Action for updating a page part resource

=cut

sub handler
{
    my ($req) = @_;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    debug "translate_page_part";

    my $q = $req->q;

    my $nid = $q->param('id') or die "nid param missing";
    my $lc = $q->param('lc') or die "lc param missing";
    my $trt = $q->param('translation') or die "translation missing";

    my $n = RDF::Base::Resource->get_by_id( $nid );
    my $l = RDF::Base::Resource->find_one({code=>$lc, is=>$C_language}, $args);

    $n->session_history_add('updated');

    unless( $n->has_value({is=>$C_website_text}, $args) )
    {
        if( $n->has_value({is=>$C_webpage}, $args) )
        {
            $n->add({ is => $C_website_text });
        }
        else
        {
            throw('validation', "The node must be a website_text");
        }
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
    my @pagen;

    if( $code =~ /^(\/[^#]+)#(.*)$/ )
    {
	my $pagecode = $1;
	my $partcode = $2;

	unless( $n->first_revprop('has_member') )
	{
	    my $pn = RDF::Base::Resource->
              set_one({ code => $pagecode,
                        is => $C_webpage,
                      },
                      $args);

	    $pn->add({ has_member => $n }, $args );
	}
    }
    else
    {
        @pagen = $n;
    }

    push @pagen, $n->revlist('has_member')->as_array;


    foreach my $pn ( @pagen )
    {
        if( not $pn->has_value({is => $C_webpage }) )
        {
            $pn->add({ is => $C_webpage }, $args );
        }
    }

    $res->autocommit;

    if( $res->changes )
    {
        debug "Publishing ".scalar(@pagen)." pages";
        foreach my $pn ( @pagen )
        {
#            debug "  Publishing ".$pn->sysdesig;
	    if( $pn->can('publish') )
	    {
		$pn->publish;
	    }
        }

	return loc("Translation changed");
    }
    else
    {
	return loc("No changes");
    }
}

1;
