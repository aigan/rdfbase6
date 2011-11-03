package Rit::Base::AJAX::arc_create;

use 5.010;
use strict;
use warnings;
use utf8;
use locale;
use JSON;

use Para::Frame::Utils  qw( debug datadump );
use Para::Frame::L10N   qw( loc );

use Rit::Base::Utils     qw( parse_propargs );

=head1 NAME

Rit::Base::AJAX::arc_create

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
    my $R         = Rit::Base->Resource;
    my $A         = Rit::Base->Arc;
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
