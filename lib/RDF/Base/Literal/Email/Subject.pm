package RDF::Base::Literal::Email::Subject;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::Email::Subject

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Literal::String );

use Carp qw( cluck confess longmess );
#use CGI;
#use MIME::Words qw( decode_mimewords );
use MIME::WordDecoder; # mime_to_perl_string

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug trim validate_utf8 );

use RDF::Base::Utils qw( is_undef );
use RDF::Base::Constants qw( $C_text );


=head1 DESCRIPTION

Represents an Email Messages Subject

=cut


##############################################################################

=head2 as_html

  $subj->as_html

=cut

sub as_html
{
    my( $subj ) = @_;

    my $orig = $subj->plain;
    my $text = $orig;

    my $re = 0;
    if( $text =~ s/\b(re|sv):s*//gi )
    {
	$re++;
    }

    my $spam = 0;
    if( $text =~ s/\[spam\]\s*//gi )
    {
	$spam++;
    }
    if( $text =~ s/\*\*\*spam\*\*\*\s*//gi )
    {
	$spam++;
    }

    my $autoreply = 0;
    if( $text =~ s/\bAutoReply:\s*//gi )
    {
	$autoreply++;
    }

    trim(\$text);

    my $out = "";

    if( $spam )
    {
	$out .= "<small>SPAM:</small> ";
    }

    if( $autoreply )
    {
	$out .= "<em>Autosvar</em> ";
    }

    if( $re )
    {
	$out .= "<big>Re:</big> ";
    }

    $out .= CGI->escapeHTML($text);

    return $out;
}


##############################################################################

=head2 as_reply

  $subj->as_reply

=cut

sub as_reply
{
    my( $subj ) = @_;

    my $orig = $subj->plain;
    my $text = $orig;

    $text =~ s/\b(re|sv):s*//gi;
    $text =~ s/^ +//;

    return "Re: $text";
}


##############################################################################

=head2 new_by_raw

  $subj->new_by_raw( $raw_subject )

=cut

sub new_by_raw
{
    my( $class, $raw ) = @_;

#    my $wd = default MIME::WordDecoder;
#    my $wd = new MIME::WordDecoder::ISO_8859 1;
#    my $subject = $wd->decode( $raw||'' );
    my $subject = mime_to_perl_string( $raw||'' );

    return $class->new_from_db($subject, $C_text);
}


##############################################################################

1;
