# -*-cperl-*-
package Rit::Base::Action::update_cache;

use strict;
use Para::Frame::Utils qw( debug );

sub handler
{
    my( $req, $params ) = @_;

    debug "update cache!";

    if( $params->{'change'} eq 'arc_created' )
    {
	my $id = $params->{'arc_id'};
	my $arc = Rit::Base::Arc->get( $id );

	$arc->subj->initiate_cache;
	$arc->initiate_cache;
	$arc->value->initiate_cache($arc);
	$arc->schedule_check_create;
    }
    elsif( $params->{'change'} eq 'arc_removed' )
    {
	# also from remove_duplicates
	if( $params->{'subj_id'} )
	{
	    my $subj = Rit::Base::Resource->get( $params->{'subj_id'} );
	    $subj->initiate_cache;
	}

	if( $params->{'arc_id'} )
	{
	    my $arc = Rit::Base::Resource->get( $params->{'arc_id'} );
	    $arc->initiate_cache;
	}

	if( $params->{'obj_id'} )
	{
	    my $obj = Rit::Base::Resource->get( $params->{'obj_id'} );
	    $obj->initiate_cache;
	}

	#$arc->value->initiate_cache(undef);
	#delete $Rit::Base::Cache::Resource{ $arc_id };
    }
    elsif( $params->{'change'} eq 'arc_updated' )
    {
	my $arc_id = $params->{'arc_id'};
	my $arc = Rit::Base::Arc->get( $arc_id );

	$arc->subj->initiate_cache;
	$arc->initiate_cache;
	$arc->value->initiate_cache($arc);
	$arc->schedule_check_create;
    }

    return "Update cache done";
}

1;