package RDF::Base::AJAX::translate_string;
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
use utf8;
use locale;
use JSON;

use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::L10N qw( loc );

use RDF::Base::Constants qw( $C_language $C_translatable );
use RDF::Base::Utils qw( parse_propargs );


=head1 NAME

RDF::Base::AJAX::translate_string

=head1 DESCRIPTION



=cut

##############################################################################

sub handler
{
    my( $class, $req ) = @_;

    my $dbix      = $RDF::dbix;
    my $q         = $req->q;
    my $id        = $q->param('id') or die('No id');
    my $new       = $q->param('value') || '';
    my $lang_code = $req->language->code;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    debug "Got id   : $id";
    debug "Got value: $new";
    debug "Language : $lang_code";

    if( $id =~ /^translate_(.*)$/ ) {
        $id = $1;
    }
    else {
        die('No c id');
    }

    my $R = RDF::Base->Resource;
    my $node = $R->get($id);

    delete $RDF::Base::L10N::TRANSLATION{ $node->translation_label };


    my $lang = RDF::Base::Resource->get({
                                         code => $lang_code,
                                         is   => $C_language,
                                        });

    my $trans = $node->first_prop('has_translation',{ is_of_language => $lang });

    if( $trans ) {
        debug "Trans är " . $trans->sysdesig;
        $trans->update({ value => $new }, $args);
    }
    else {
        $trans = RDF::Base::Literal::String->new( $new );
        debug "Trans är " . $trans->sysdesig;
        $node->add({ has_translation => $trans,
		     is => $C_translatable,
		   }, $args);
        $trans->add({ is_of_language => $lang }, $args);
    }

    $res->autocommit({ activate => 1 });

    return $node->loc(qw([_1] [_2] [_3] [_4] [_5]));
}


1;
