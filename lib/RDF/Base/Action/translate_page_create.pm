package RDF::Base::Action::translate_page_create;
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

use Para::Frame::Utils qw( throw );
use Para::Frame::L10N qw( loc );

use RDF::Base::Resource;
use RDF::Base::Constants qw( $C_webpage );
use RDF::Base::Utils qw( is_undef parse_propargs );

=head1 DESCRIPTION

RDFbase Action for creating a page resource

=cut

sub handler
{
    my ($req) = @_;

    my $q = $req->q;

    my $page_base = $q->param('page_path_base') or die "page base missing";

    if( $page_base =~ /\./ )
    {
	throw('validation', "Malformed page base");
    }

    my $props =
    {
     is => $C_webpage,
     code => $page_base,
    };

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $n = RDF::Base::Resource->create( $props, $args );
    $n->session_history_add('updated');

    $q->param('id' => $n->id );


    $res->autocommit;

    if( $res->changes )
    {
	return loc("Page created");
    }
    else
    {
	return loc("No changes");
    }
}

1;
