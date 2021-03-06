package RDF::Base::Renderer::GraphViz;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;
use base 'Para::Frame::Renderer::Custom';

use GraphViz;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw datadump uri );

use RDF::Base::Utils qw( truncstring );


##############################################################################

our @handled;


sub render_output
{
	my( $rend ) = @_;

	@handled = ();

	my $req = $rend->req;
	$req->require_root_access;
	my $q = $req->q;
	my $R = RDF::Base->Resource;

	my $layout = $q->param('layout') || 'dot';

	my $g = GraphViz->new( layout => $layout,
												 #overlap => 'false',
												 edge => {
																	#len => 3,
																	fontsize => 10,
																 },
												 node => {
																	shape => 'ellipse',
																	style => 'filled',
																 },
											 );

	my $id = $q->param('id') or throw('incomplete', "Saknar ID");
	my $node = $R->get($id);

	my @expand = $q->param('expand');

	nodes_arcs( $q, $g, $node, \@expand );

	debug "GraphViz output " . $g->as_debug;

	my $out = $g->as_svg;
	$out =~ s/scale\(1.33333 1.33333\)//;


	return \$out;
}


sub nodes_arcs
{
	my( $q, $g, $node, $expand, $revs ) = @_;

	my $nodeid = $node->id;
	return
		if ( grep(/$nodeid/, @handled) );

	push @handled, $node->id;

	debug "Getting arcs for ". $node->id;
	debug "Expand is: ". join(', ', @$expand);

	my @labels;

	push @labels, "-*- ". $node->sysdesig ." -*-";

	$g->add_node( $node->id );

	my $arclist = $node->arc_list( undef, undef, [['active', 'direct']] );

	while ( my $arc = $arclist->get_next_nos )
	{
		next
			if ( $arc->pred->plain eq 'name' );

		my $value = $arc->value;
		if ( $arc->coltype eq 'obj')
		{
	    my $valueid = $value->id;
	    if ( grep(/$valueid/, @$expand ) )
	    {
				nodes_arcs( $q, $g, $value, $expand, $revs );
	    }
	    else
	    {
				debug "uri:".  $q->url(-query => 1);
				$g->add_node( $value->id,
											label => $value->desig,
											URL => $q->escapeHTML(uri( $q->url(-query => 1), { expand => $value->id })),
										);
	    }

	    $g->add_edge( $node->id, $value->id, label => $arc->pred->plain );
		}
		else
		{
	    push @labels, $arc->pred->plain ." --> ". truncstring($value->literal);
	    #debug "Valtype is: ". $arc->valtype->desig;
	    #$g->add_edge( $node->sysdesig, $value->plain, label => $arc->pred->plain );
	    #
	    #if( $arc->valtype->is('textbox') or $arc->valtype->is('accumulative_text'))
	    #{
	    #	push @labels, $arc->pred->plain ." --> ". truncstring($value->literal);
	    #	#$g->add_node( $value->plain, shape => 'box' );
	    #}
	    #else
	    #{
	    #	push @labels, $arc->pred->plain ." --> ". $value->literal;
	    #	#$g->add_node( $value->plain, shape => 'box' );
	    #}
		}
	}

	$g->add_node( $node->id, label => join('\n', @labels) );
}


##############################################################################

sub set_ctype
{
	debug "setting ctype";
	$_[1]->set("image/svg+xml");
}


##############################################################################

1;
