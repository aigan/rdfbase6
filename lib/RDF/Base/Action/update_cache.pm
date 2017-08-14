package RDF::Base::Action::update_cache;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Para::Frame::Utils qw( debug );

use RDF::Base::Resource;

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
	    if( my $n = $RDF::Base::Cache::Resource{ $id } )
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
	    my $n = RDF::Base::Resource->get( $id );
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
	    if( my $n = $RDF::Base::Cache::Resource{ $id } )
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
