package Rit::Base::Action::node_update;
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

use Para::Frame::L10N qw( loc );
use Para::Frame::Utils qw( throw debug );

use Rit::Base::Literal::Time qw( now );
use Rit::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

Ritbase Action for editing nodes.

This will always create a node record for holding creatin and updated
times.

=cut

sub handler
{
    my( $req ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q = $req->q;

    my $id = $q->param('id');
    unless( $id )
    {
	throw('incomplete', "Id missing");
    }

    my $node = Rit::Base::Resource->get($id);

    unless( $req->session->user->level >= 20
	    or $node->is_owned_by( $req->session->user )
	  )
    {
	throw('denied', "Access denied");
    }

    if( $q->param('prop_label') )
    {
	$node->set_label( $q->param('prop_label') );
	$q->delete('prop_label');
    }

    $node->update_by_query($args);

    if( $res->changes )
    {
	unless( $node->has_node_record )
	{
	    $node->create_rec;
	}
    }

    $res->autocommit;


    if( $res->changes )
    {
	return loc("Changes saved");
    }
    else
    {
	return loc("No changes");
    }
}


1;
