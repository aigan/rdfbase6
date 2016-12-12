package RDF::Base::AJAX::arc_update;
#=============================================================================
#
# AUTHOR
#		Jonas Liljegren		<jonas@paranormal.se>
#
# COPYRIGHT
#		Copyright (C) 2005-2011 Avisita AB.	 All Rights Reserved.
#
#		This module is free software; you can redistribute it and/or
#		modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;
use utf8;
use locale;
use JSON;

use Carp qw( cluck confess croak carp shortmess );

use Para::Frame::Utils	qw( debug datadump );
use Para::Frame::L10N		qw( loc );

use RDF::Base::Utils		 qw( parse_propargs parse_form_field_prop );

use RDF::Base::Widget::Handler;

=head1 NAME

RDF::Base::AJAX::arc_update

=head1 DESCRIPTION

For updating LITERAL arcs.

=cut

##############################################################################

sub handler
{
	my( $class, $req ) = @_;

	my( $args, $arclim, $res ) = parse_propargs('auto');

	my $q					= $req->q;
	my $out				= '';
	my $R					= RDF::Base->Resource;
	my $A					= RDF::Base->Arc;
	my $param			= $q->param('id');
	my $value			= $q->param('value');

	my $arg				= parse_form_field_prop($param);
	my $subj			= $arg->{'subj'};
	my $arc_id		= $arg->{'arc' };

	if ( $subj )
	{
		unless( $subj =~ /^(\d+)$/ )
		{
			confess "Invalid subj part: $subj";
		}

		$subj = $R->get($subj);
		debug 2, "subj gave ".$subj->sysdesig;
	}
	elsif ( $arc_id )
	{
		my $arc = $A->get($arc_id);
		$subj = $arc->subj;
	}

	confess "No subj in arc_update"
		unless $subj;


	$subj->RDF::Base::Widget::Handler::handle_query_arc_value($param, $value, $args, 1);
	$res->autocommit;

	return $value;
}


1;
