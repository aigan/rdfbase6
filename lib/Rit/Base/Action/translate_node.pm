#  $Id$  -*-cperl-*-
package Rit::Base::Action::translate_node;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Action for translating a node
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use strict;
use Carp qw( confess );

use Para::Frame::Utils qw( throw debug trim datadump );
use Para::Frame::L10N qw( loc );


use Rit::Base::Resource;
use Rit::Base::String;
use Rit::Base::Utils qw( is_undef parse_propargs );

use Rit::Base::Constants qw( $C_language );

sub handler
{
    my ($req) = @_;

    my $q = $req->q;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $id = $q->param('id') or die "id param missing";
    my $pred_in = $q->param('pred') or die "pred param missing";

    my $n = Rit::Base::Resource->get_by_id( $id );

    my $p = Rit::Base::Pred->get( $pred_in );

    $n->session_history_add('updated');

    foreach my $key ( $q->param )
    {
	next unless $key =~ /^arc_(\d+)_val$/;
	my $aid = $1;
	debug "Checking $aid";

	my $arc = Rit::Base::Arc->get_by_id( $aid );

	my $val_new = $q->param("arc_${aid}_val");
	trim(\$val_new);
	my $weight_in = $q->param("arc_${aid}_weight");
	my $weight_new = Rit::Base::String->new($weight_in)||is_undef;

	if( my $obj = $arc->obj ) # value node (with lang or weight)
	{
	    unless( length $val_new ) # Remove?
	    {
		$arc->obj->remove($args);
		next;
	    }

	    my $val_old = $obj->desig($args);
	    if( $val_new ne $val_old )
	    {
		$obj->update({'value' => $val_new }, $args);
	    }

#	    debug "BEFORE ".datadump($obj, 2); ### DEBUG
	    my $weight_old = $obj->first_prop('weight');
	    debug "  old weight is $weight_old";
	    debug "  new weight is $weight_new";
	    if( $weight_new != $weight_old )
	    {
#		debug "AFTER ".datadump($obj, 2); ### DEBUG
		if( $weight_new->defined )
		{
		    $obj->update({ 'weight' => $weight_new }, $args);
		}
		else
		{
		    $obj->arc('weight')->remove( $args );
		}
	    }
	}
	else # Not a value node
	{
	    unless( length $val_new ) # Remove?
	    {
		$arc->remove( $args );
		next;
	    }

	    my $val_old = $arc->value;
	    if( $val_new ne $val_old )
	    {
		$arc->set_value($val_new, $args);
	    }

	    my $props = {};
	    if( my $lc = $q->param("arc_${aid}_is_of_language") )
	    {
		my $l = Rit::Base::Resource->get({
						  code=>$lc,
						  is=>$C_language,
						 },
						 $args);
		$props->{'is_of_language'} = $l;
	    }

	    if( my $weight_new = $q->param("arc_${aid}_weight") )
	    {
		$props->{'weight'} = $weight_new;
	    }

	    $arc->value->update($props, $args);
	}
    }

    my $new_val = $q->param('new_val');
    trim(\$new_val);
    if( length $new_val ) # Create new translation
    {
	my $lit = Rit::Base::String->new($new_val);
	$n->add({ $p->plain => $lit }, $args );

	my $props = {};
	if( my $lc = $q->param("new_is_of_language") )
	{
	    my $l = Rit::Base::Resource->get({
					      code=>$lc,
					      is=>$C_language,
					     },
					    $args );
	    $props->{'is_of_language'} = $l;
	}

	if( my $weight_new = $q->param("new_weight") )
	{
	    $props->{'weight'} = $weight_new;
	}

	$lit->update($props, $args);
    }

    $q->delete('new_val');
    $q->delete("new_is_of_language");
    $q->delete("new_weight");

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
