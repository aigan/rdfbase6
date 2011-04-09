package Rit::Base::Action::translate_node;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-20011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Carp qw( confess );

use Para::Frame::Utils qw( throw debug trim datadump );
use Para::Frame::L10N qw( loc );


use Rit::Base::Resource;
use Rit::Base::Literal::String;
use Rit::Base::Utils qw( is_undef parse_propargs );

use Rit::Base::Constants qw( $C_language );

=head1 DESCRIPTION

Ritbase Action for translating a node

=cut

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
        my $arc_in = $arc;

	my $val_new = $q->param("arc_${aid}_val");
	trim(\$val_new);
	my $weight_new = $q->param("arc_${aid}_weight") || 0;
#	my $weight_new = Rit::Base::Literal::String->new($weight_in)||is_undef;

	if( my $obj = $arc->value_node )
	{
	    unless( length $val_new ) # Remove?
	    {
		$arc->obj->remove($args);
		next;
	    }

	    my $val_old = $obj->first_literal->desig($args);
	    if( $val_new ne $val_old )
	    {
                debug "'$val_old' != '$val_new'"; # New value trimmed?
		$arc = $arc->set_value($val_new, $args);
	    }

#	    debug "BEFORE ".datadump($obj, 2); ### DEBUG
	    my $weight_old = $arc->weight || $obj->first_prop('weight') || 0;
	    debug "  old weight is $weight_old";
	    debug "  new weight is $weight_new";
	    if( $weight_new != $weight_old )
	    {
#		debug "AFTER ".datadump($obj, 2); ### DEBUG

                $arc->set_weight($weight_new, $args);
                if( my $aw = $obj->arc('weight') )
                {
                    $aw->remove( $args );
                }

#		if( $weight_new->defined )
#		{
#		    $obj->update({ 'weight' => $weight_new }, $args);
#		}
#		else
#		{
#		    $obj->arc('weight')->remove( $args );
#		}
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
                debug "'$val_old' != '$val_new'"; # New value trimmed?
		$arc = $arc->set_value($val_new, $args);
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

            my $weight_old = $arc->weight || 0;
            my $weight_new = $q->param("arc_${aid}_weight") || 0;
	    if( $weight_new != $weight_old )
	    {
                $arc = $arc->set_weight($weight_new, $args);
	    }

#            debug "updating value with ".datadump($props,1);
	    $arc->value->update($props, $args);
	}
    }

    my $new_val = $q->param('new_val');
    trim(\$new_val);
    if( length $new_val ) # Create new translation
    {
        my $weight_new = $q->param("new_weight") || 0;
	my $arc = $n->add_arc({ $p->plain => $new_val }, {%$args, arc_weight => $weight_new} );
	# The arc may already exist

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

	$arc->value->update($props, $args);
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
