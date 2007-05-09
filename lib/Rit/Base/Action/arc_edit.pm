#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_edit;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for updating arcs
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

use Para::Frame::Utils qw( clear_params debug );

use Rit::Base::Utils qw( parse_arc_add_box );

sub handler
{
    my( $req ) = @_;

    my $changed = 0;

    my $q = $req->q;
    my $arc_id = $q->param('arc_id');

    my $pred_name      = $q->param('pred');
    my $value          = $q->param('val');
    my $literal_arcs   = $q->param('literal_arcs');
    my $explicit       = $q->param('explicit');
    my $check_explicit = $q->param('check_explicit');

    clear_params qw(pred val literal_arcs explicit check_explicit);

    my $arc = Rit::Base::Arc->get( $arc_id );

    # Indirect arc
    #
    if( $check_explicit )
    {
	if( $arc->explicit <=> $explicit )
	{
	    $arc->set_explicit( $explicit );
	    $changed ++;
	}
    }
    #
    # Direct arc (keep)
    #
    elsif( $pred_name )
    {
	my $new = $arc->set_pred( $pred_name, \$changed );
	$new = $new->set_value( $value, \$changed );
	debug "New arc is ".$new->sysdesig;
	debug "Changes: $changed";

	# Should we transform this literal to a value node?
	my $props = parse_arc_add_box( $literal_arcs );
	$new->value->update( $props, \$changed );

	if( $changed )
	{
	    $arc_id = $new->id;
	    $q->param('arc_id', $arc_id);
	    return "Arc $arc_id created as a new version";
	}
    }
    #
    # Direct arc (remove)
    #
    else
    {
	my $subj = $arc->subj;
	if( $arc->remove )
	{
	    $q->param('id', $subj->id);
	    my $home = $req->site->home_url_path;
	    $req->set_page_path("/rb/node/update.tt");
	    return "Arc $arc_id removed";
	}
    }


    if( $changed )
    {
	return "Arc $arc_id updated";
    }
    return "Arc $arc_id unchanged";
}


1;
