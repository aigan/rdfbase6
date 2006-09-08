#  $Id$  -*-cperl-*-
package Rit::Guides::Action::translate_node;

use strict;

use Data::Dumper;

use Para::Frame::Utils qw( throw debug trim datadump );

use Rit::Base::Resource;
use Rit::Base::String;
use Rit::Base::Utils qw( is_undef );

use Rit::Base::Constants qw( $C_language );

sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $id = $q->param('id') or die "id param missing";
    my $pred_name = $q->param('pred') or die "pred param missing";

    my $n = Rit::Base::Resource->get_by_id( $id );

    my $p = Rit::Base::Pred->get( $pred_name );


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

	if( my $obj = $arc->obj )
	{
	    unless( length $val_new ) # Remove?
	    {
		$arc->obj->remove;
		next;
	    }

	    my $val_old = $obj->desig;
	    if( $val_new ne $val_old )
	    {
		$obj->update('value'=>$val_new);
	    }

#	    debug "BEFORE ".datadump($obj, 2); ### DEBUG
	    my $weight_old = $obj->weight;
	    debug "  old weight is $weight_old";
	    debug "  new weight is $weight_new";
	    if( $weight_new != $weight_old )
	    {
#		debug "AFTER ".datadump($obj, 2); ### DEBUG
		if( $weight_new->defined )
		{
		    $obj->update('weight'=>$weight_new);
		}
		else
		{
		    $obj->arc('weight')->remove;
		}
	    }
	}
	else
	{
	    unless( length $val_new ) # Remove?
	    {
		$arc->remove;
		next;
	    }

	    my $val_old = $arc->value;
	    if( $val_new ne $val_old )
	    {
		$arc->set_value($val_new);
	    }

	    my $props = {};
	    if( my $lc = $q->param("arc_${aid}_language") )
	    {
		my $l = Rit::Base::Resource->get({code=>$lc, is=>$C_language});
		$props->{'language'} = $l;
	    }

	    if( my $weight_new = $q->param("arc_${aid}_weight") )
	    {
		$props->{'weight'} = $weight_new;
	    }

	    $arc->value->update($props);
	}
    }

    my $new_val = $q->param('new_val');
    trim(\$new_val);
    if( length $new_val ) # Create new translation
    {
	my $lit = Rit::Base::String->new($new_val);
	$n->add($p => $lit );

	my $props = {};
	if( my $lc = $q->param("new_language") )
	{
	    my $l = Rit::Base::Resource->get({code=>$lc, is=>$C_language});
	    $props->{'language'} = $l;
	}

	if( my $weight_new = $q->param("new_weight") )
	{
	    $props->{'weight'} = $weight_new;
	}

	$lit->update($props);
    }

    $q->delete('new_val');
    $q->delete("new_language");
    $q->delete("new_weight");

    $req->change->report;
    return "Översättning ändrad";
}

1;
