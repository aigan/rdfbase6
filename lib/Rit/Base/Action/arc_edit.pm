package Rit::Base::Action::arc_edit;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Carp qw( confess );

use Para::Frame::Utils qw( clear_params debug );

use Rit::Base::Utils qw( parse_arc_add_box );
use Rit::Base::Resource::Change;

=head1 DESCRIPTION

Ritbase Action for updating arcs

=cut

sub handler
{
    my( $req ) = @_;
    $req->require_root_access;

    my $q = $req->q;
    my $arc_id = $q->param('arc_id');

    my $pred_name      = $q->param('pred');
    my $value          = $q->param('val');
    my $literal_arcs   = $q->param('literal_arcs');
    my $weight         = $q->param('weight') || 0;
    my $explicit       = $q->param('explicit') || 0;
    my $check_explicit = $q->param('check_explicit');
    my $force          = $q->param('force');
    my $remove         = $q->param('remove');

    clear_params qw(pred val literal_arcs explicit check_explicit);

    my $arc = Rit::Base::Arc->get( $arc_id );

    my $res = Rit::Base::Resource::Change->new;
    my $args = { res => $res };

    if( $force )
    {
	$args->{'force'} = 1;
    }

    if( $remove ) # Could also remove by setting pred_name to false
    {
	$pred_name = undef;
    }

    # Indirect arc
    #
    if( $check_explicit )
    {
	if( $arc->explicit <=> $explicit )
	{
	    confess "Not implemented";
#	    $arc->set_explicit( $explicit );
	}
    }
    #
    # Direct arc (keep)
    #
    elsif( $pred_name )
    {
	my $submit = 0;
	if( $arc->submitted )
	{
	    $submit = 1;
	    $arc->unsubmit;
	}

	my $new = $arc->set_pred( $pred_name, $args );
	$new = $new->set_value( $value, $args );
	debug "New arc is ".$new->sysdesig;

	# Should we transform this literal to a value node?
	my $props = parse_arc_add_box( $literal_arcs, $args );
	$new->value->update( $props, $args );

	if( $submit )
	{
	    $arc->submit;
	}

        my $weight_old = $arc->weight || 0;
        if( $weight != $weight_old )
        {
            if( $new->equals($arc ) )
            {
                $new = $new->set_weight($weight, $args); # New version
            }
            else
            {
                $new->set_weight($weight, {%$args,force_same_version=>1});
            }
        }

	$arc->subj->session_history_add('updated');

	$res->autocommit;

	if( $res->changes )
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
	if( $arc->submitted )
	{
	    $arc->unsubmit;
	}

	my $subj = $arc->subj;
	if( $arc->remove( $args ) )
	{
	    $res->autocommit;

	    $q->param('id', $subj->id);
	    my $home = $req->site->home_url_path;
	    $req->set_page_path("/rb/node/update.tt");
	    return "Arc $arc_id removed";
	}
    }


    if( $res->changes )
    {
	return "Arc $arc_id updated";
    }
    return "Arc $arc_id unchanged";
}


1;
