#  $Id$  -*-cperl-*-
package Rit::Base::Action::update_cache;
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

use Para::Frame::Utils qw( debug );

use Rit::Base::Resource;

=head1 DESCRIPTION

Updating cache?

=cut

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
		    $n->subj->reset_cache;
		    $n->value->reset_cache($n);
		}
		$n->reset_cache;
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
		$n->subj->reset_cache;
		$n->value->reset_cache($n);
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
		    $n->subj->reset_cache;
		    $n->value->reset_cache($n);
		}
		$n->reset_cache;
	    }
	}
    }

    return "Update cache done";
}

1;
