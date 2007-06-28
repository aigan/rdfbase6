#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_add;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for adding arcs
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

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( parse_arc_add_box parse_propargs );

sub handler
{
    my( $req ) = @_;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $DEBUG = 0;

    my $q = $req->q;
    my $subj_id = $q->param('id');

    my $query = $q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );

    my $props = parse_arc_add_box( $query );

    if( $subj_id )
    {
	my $subj = Rit::Base::Arc->get( $subj_id ); # Arc or node

	warn Dumper $props if $DEBUG;

	$subj->add( $props, $args );
	$res->autocommit;
	return "Updated node $subj_id" if $res->changes;
	return "No changes to node $subj_id";
    }
    else
    {
	my $subj = Rit::Base::Resource->create( $props, $args );
	$q->param('id', $subj->id);
	$res->autocommit;

	return sprintf("Created node %d", $subj->id);
    }
}


1;
