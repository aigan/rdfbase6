package RDF::Base::AJAX::arc_create;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;
use utf8;
use locale;
use JSON;

use Para::Frame::Utils  qw( debug datadump );
use Para::Frame::L10N   qw( loc );

use RDF::Base::Utils     qw( parse_propargs );

=head1 NAME

RDF::Base::AJAX::arc_create

=head1 DESCRIPTION

For creating LITERAL arcs.

=cut

##############################################################################

sub handler
{
    my( $class, $req ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q         = $req->q;
    my $out       = '';
    my $R         = RDF::Base->Resource;
    my $A         = RDF::Base->Arc;
    my $id        = $q->param('id');
    my $new_text  = $q->param('value');

    $id =~ s/arc_//;

    my $arc = $A->get($id);

    $arc->set_value($new_text, $args);
    $res->autocommit;

#    return $arc->value;
    return $new_text;
}


1;
