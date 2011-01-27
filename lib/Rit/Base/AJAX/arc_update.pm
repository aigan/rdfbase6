package Rit::Base::AJAX::arc_update;
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
use utf8;
use locale;
use JSON;

=head1 NAME

Rit::Base::AJAX::arc_update

=head1 DESCRIPTION

For updating LITERAL arcs.

=cut

##############################################################################

sub handler
{
    my( $class, $req ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q         = $req->q;
    my $out       = '';
    my $R         = Rit::Base->Resource;
    my $A         = Rit::Base->Arc;
    my $id        = $q->param('id');
    my $new_text  = $q->param('value');

    my $arc = $A->get($id);

    $arc->set_value($new_text, $args);
    $res->autocommit;

    return $arc->value;
}


1;
