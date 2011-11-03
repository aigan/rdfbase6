package Rit::Base::Renderer::RDF;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;
use utf8;
use base 'Para::Frame::Renderer::Custom';

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw datadump
			   trim package_to_module compile );
#use Para::Frame::L10N qw( loc );

#use Rit::Base::Utils qw( arc_lock arc_unlock );



##############################################################################

sub render_output
{
    my( $rend ) = @_;

    debug "Rendering RDF response.";

    my $req = $rend->req;
    my $R = Rit::Base->Resource;

    my( $file ) = ( $rend->url_path =~ /\/rdf\/(.*?)$/ );
    my $out = "";

    if( $file =~ /\W/ )
    {
        die "Not an id: $file";
    }
    debug "FILE: $file";

    my $rdfns = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
    $out .= qq(<?xml version="1.0"?>\n);
    $out .= qq(<rdf:RDF xmlns:rdf="$rdfns"\n);
    $out .= qq(xmlns:rb="http://jonas.rit.se/~joli/hg/rb/rdf/">\n);

    my $n = $R->get($file);
    foreach my $pred ( $n->list_preds->as_array )
    {
        $out .= $n->arc($pred)->as_rdf;
    }

    $out .= qq(</rdf:RDF>\n);
    return \$out;
}


##############################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    unless( $ctype )
    {
        die "No ctype given to set";
    }

     $ctype->set("application/rdf+xml; charset=UTF-8");
}


##############################################################################

1;
