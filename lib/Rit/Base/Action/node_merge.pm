#  $Id$  -*-cperl-*-
package Rit::Base::Action::node_merge;
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

use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::L10N qw( loc );

use Rit::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

Ritbase Action for merging nodes

=cut

sub handler
{
    my( $req ) = @_;

    throw('denied', "Nope") unless $req->session->user->level >= 20;

    my $q = $req->q;
    my $id = $q->param('id');
    my $move_literals = $q->param('move_literals') || 0;

    my $node1 = Rit::Base::Resource->get( $id );
    my $node2;
    if( my $id2 = $q->param('id2') )
    {
	$node2 = Rit::Base::Resource->get( $id2 );
    }
    else
    {
	my $result = $Para::Frame::REQ->result;
	my $desig2 = $q->param('node2_desig') or
	    throw('incomplete', "Ange nod add slå samman med");

	my $node_list = Rit::Base::Resource->find({
	    'predor_name_-_code_-_name_short' => $desig2,
	});


	# Remove itself
	my @node_list_out = grep not( $node1->equals($_) ), @$node_list;
#	my @node_list_out = @$node_list;

	if( @node_list_out )
	{
	    $result->{'info'}{'alternatives'}{'alts'} = \@node_list_out;
	    $req->set_page($req->referer_path);
	    throw('alternatives', "välj nod att slå samman med");
	}
	else
	{
	    debug datadump $result->{'info'};
	    throw('validation', "No nodes matches the given name");
	}
    }

    my( $args, $arclim, $res ) = parse_propargs();
    $args->{'move_literals'} = $move_literals;

    $node1->merge_node( $node2, $args );

    $node2->session_history_add('updated');

    $res->autocommit;

    $q->param('id', $node2->id );

    if( $res->changes )
    {
	return loc("Resources merged");
    }
    else
    {
	return loc("No changes");
    }
}


1;
