# -*-cperl-*-
package Rit::Base::Action::update_cache;

use strict;

use Para::Frame::Utils qw( debug );

use Rit::Base::Resource;

sub handler
{
    my( $req, $params ) = @_;

#    debug "update cache!";

    if( $params->{'removed'} )
    {
	foreach my $id ( split ',', $params->{'removed'})
	{
	    if( my $n = $Rit::Base::Cache::Resource{ $id } )
	    {
		if( $n->is_arc )
		{
		    $n->subj->initiate_cache;
		    $n->value->initiate_cache($n);
		}
		$n->initiate_cache;
	    }
	}
    }

    if( $params->{'created'} )
    {
	foreach my $id ( split ',', $params->{'created'})
	{
	    my $n = Rit::Base::Resource->get( $id );
	    if( $n->is_arc )
	    {
		# In case subj or obj is in memory
		$n->subj->initiate_cache;
		$n->value->initiate_cache($n);
	    }
	}
    }

    if( $params->{'updated'} )
    {
	foreach my $id ( split ',', $params->{'updated'})
	{
	    if( my $n = $Rit::Base::Cache::Resource{ $id } )
	    {
		if( $n->is_arc )
		{
		    $n->subj->initiate_cache;
		    $n->value->initiate_cache($n);
		}
		$n->initiate_cache;
	    }
	}
    }

    return "Update cache done";
}

1;
