package Rit::Base::AJAX::translate_string;
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

use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::L10N qw( loc );

use Rit::Base::Constants qw( $C_language );
use Rit::Base::Utils qw( parse_propargs );


=head1 NAME

Rit::Base::AJAX::translate_string

=head1 DESCRIPTION



=cut

##############################################################################

sub handler
{
    my( $class, $req ) = @_;

    my $dbix      = $Rit::dbix;
    my $q         = $req->q;
    my $id        = $q->param('id') or die('No id');
    my $new       = $q->param('value') || '';
    my $lang_code = $req->language->code;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    debug "Got id   : $id";
    debug "Got value: $new";

    if( $id =~ /^translate_(.*)$/ ) {
        $id = $1;
    }
    else {
        die('No c id');
    }

    my $R = Rit::Base->Resource;
    my $node = $R->get($id);

    delete $Rit::Base::L10N::TRANSLATION{ $node->translation_label };


    my $lang = Rit::Base::Resource->get({
                                         code => $lang_code,
                                         is   => $C_language,
                                        });

    my $trans = $node->has_translation({ is_of_language => $lang })->get_first_nos;

    if( $trans ) {
        debug "Trans är " . $trans->sysdesig;
        $trans->update({ value => $new }, $args);
    }
    else {
        $trans = Rit::Base::Literal::String->new( $new );
        debug "Trans är " . $trans->sysdesig;
        $node->add({ has_translation => $trans }, $args);
        $trans->add({ is_of_language => $lang }, $args);
    }

    $res->autocommit({ activate => 1 });

    return loc( $node->translation_label ); # Redo translation, to get [_1] etc right.
}


1;
