package Rit::Base::Action::vacuum;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Para::Frame::L10N qw( loc );

use Rit::Base::Resource;
use Rit::Base::Utils qw( parse_propargs );

=head1 DESCRIPTION

Ritbase Action for repairing a resource

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $id = $q->param('id');
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $node = Rit::Base::Resource->get( $id );
    $node->reset_cache(undef, $args );
    $node->vacuum($args);
    $node->session_history_add('updated');

    $res->autocommit;

    if( $res->changes )
    {
	return loc("Resource vacuumed");
    }
    else
    {
	return loc("No changes");
    }
}


1;
