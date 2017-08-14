package RDF::Base::Action::vacuum;
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

use Para::Frame::L10N qw( loc );

use RDF::Base::Resource;
use RDF::Base::Utils qw( solid_propargs );

=head1 DESCRIPTION

RDFbase Action for repairing a resource

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $id = $q->param('id');
    my( $args, $arclim, $res ) = solid_propargs({
                                                 activate_new_arcs => 1,
                                                 no_notification => 1,
                                                });

    my $node = RDF::Base::Resource->get( $id );
    $node->reset_cache(undef, $args );
    $node->vacuum_node($args);
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
