package Rit::Base::AJAX::arc_update;

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
