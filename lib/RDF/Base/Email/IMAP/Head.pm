package RDF::Base::Email::IMAP::Head;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::IMAP::Head

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( RDF::Base::Email::Head );

use Carp qw( croak confess cluck );
use URI;
#use MIME::WordDecoder qw( mime_to_perl_string );
use IMAP::BodyStructure;
use MIME::QuotedPrint qw(decode_qp);
use MIME::Base64 qw( decode_base64 );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug idn_encode idn_decode datadump catch fqdn );
use Para::Frame::L10N qw( loc );

use RDF::Base;
use RDF::Base::List;
use RDF::Base::Utils qw( parse_propargs is_undef );
use RDF::Base::Literal::String;



##############################################################################

=head2 new_by_uid

Taken from L<Mail::IMAPClient/parse_headers>

=cut

sub new_by_uid
{
    my( $class, $folder, $uid ) = @_;

    my $raw = $folder->imap_cmd('fetch',
				"$uid BODY.PEEK[HEADER]");

#    debug "New IMAP head by uid $uid"; ### DEBUG

    my $headers = ""; # original string
    my $msgid;
    my $h = 0;   # in header

    # NOTE: Taken from Mail::IMAPClient/parse_headers
    #
    # TODO: simplify!!!
    #
    # $raw is a arrayref looking like:
    # [
    #  '5 UID FETCH 1605 BODY.PEEK[HEADER]',
    #  '* 1598 FETCH (UID 1605 BODY[HEADER]',
    #  'Return-Path: <konferens@rfsl.se>
    #  Delivered-To: avisita.com_rg-tickets@skinner.ritweb.se
    #  Received: from mail.rit.se (mail.rit.se [213.88.173.41])
    #    (using TLSv1 with cipher DHE-RSA-AES256-SHA (256/256 bits))
    #    (No client certificate requested)
    #    by skinner.ritweb.se (Postfix) with ESMTP id B1F4810580A4
    #    for <avisita.com_rg-tickets@skinner.ritweb.se>; Wed, 30 Jan 2008 17:10:25 +0100 (CET)
    # .....
    #  ',
    #  ')
    #  ',
    #  '5 OK FETCH completed.
    #  '
    # ];

    foreach my $header (map {split /\r?\n/} @$raw)
    {
	# little problem: Windows2003 has UID as body, not in header
        if(
	   $header =~ s/^\* \s+ (\d+) \s+ FETCH \s+
                        \( (.*?) BODY\[HEADER (?:\.FIELDS)? .*? \]\s*//ix)
        {
	    # start new message header
            ($msgid, my $msgattrs) = ($1, $2);
	    $h = 1;
            $msgid = $msgattrs =~ m/\b UID \s+ (\d+)/x ? $1 : undef;
        }

        $header =~ /\S/ or next; # skip empty lines.

        # ( for vi
        if($header =~ /^\)/)  # end of this message
        {
	    $h = 0; # inbetween headers
            next;
        }
        elsif(!$msgid && $header =~ /^\s*UID\s+(\d+)\s*\)/)
        {
	    $h = 0;
            next;
        }

        unless( $h )
        {
	    last if $header =~ / OK /i;
            debug(2, "found data between fetch headers: $header");
            next;
        }

	$headers .= $header . "\n";
    }

#    debug $headers;

    return $class->new( \$headers );
}


##############################################################################

=head2 new_body_head_by_part_env

Takes a IMAP::BodyStructure::Envelope

=cut

sub new_body_head_by_part_env
{
    my( $class, $env ) = @_;


#    debug "Initializing body head from part env";
#    debug datadump($env);

    my $head = $class->new("");
    return $head unless $env;


    foreach my $field (qw( date subject message-id in-reply-to ))
    {
	my $key = $field; $key =~ s/-/_/g;

	if( my $val = $env->{$key} )
	{
#	    debug "  $field: $val";
	    $head->header_set($field, $val );
	}
    }

    foreach my $field (qw( to from cc bcc sender reply-to ))
    {
	my $key = $field; $key =~ s/-/_/g;
	my $val = $env->{$key};

	if( $val and ref($val)eq'ARRAY' and @{$env->{$key}} )
	{
	    my @vals = map $_->{full}, @{$env->{$key}};
#	    debug "  $field: @vals";
	    $head->header_set($field, @vals );
	}
    }

    return $head;
}


##############################################################################

=head2 new_body_head_by_part

Import the full headers

=cut

sub new_body_head_by_part
{
    my( $class, $part ) = @_;

    debug "Initializing body head from part ".$part->path;

    my $email = $part->email;
    my $folder = $email->folder;
    my $uid = $part->top->uid or die "No uid";
    my $imap_path = $part->path;

    # Read the header, but not the body


    my $chunk_size = 1000;
    my $data = "";
    my $pos = 0;

    debug "bodypart_string($uid,'$imap_path',$chunk_size,$pos)";

    my $chunk = $folder->imap_cmd('bodypart_string',
				  $uid, $imap_path,
				  $chunk_size, $pos,
				 );
    debug "Reading header from pos $pos";
    while( my $len = length $chunk )
    {
	debug "Got $len bytes";

	if( $chunk =~ s/(\r?\n\r?\n).*/$1/s )
	{
	    $data .= $chunk;
	    last;
	}

	$data .= $chunk;
	$pos += $len;

#	debug "Reading header from pos $pos";
	$chunk = $folder->imap_cmd('bodypart_string',
				   $uid, $imap_path,
				   $chunk_size, $pos,
				  );
    }

    debug "Got header:\n$data";

    return $class->new( \$data );
}


##############################################################################

=head2 new_by_part

Import the full headers

=cut

sub new_by_part
{
    my( $class, $part ) = @_;

#    debug "Initializing head from part ".$part->path;

    my $email = $part->email;
    my $folder = $email->folder;
    my $uid = $part->top->uid or die "No uid";
    my $imap_path = $part->path;

    # Read the header, but not the body

    my $raw = $folder->imap_cmd('fetch',
				"$uid BODY.PEEK[$imap_path.HEADER]");


    # $raw is a arrayref looking like:
# [
#            '42 UID FETCH 4867 BODY.PEEK[2.2.HEADER]',
#            '* 4859 FETCH (UID 4867 BODY[2.2.HEADER]',
#            'Received: from mail.rit.se ...
#  MIME-Version: 1.0
#  User-Agent: Thunderbird 2.0.0.19 (Windows/20081209)
#  Date: Wed, 25 Feb 2009 11:30:17 +0100
#  Reply-To: anne-louise.larsson@avisita.com
#  X-Virus-Scanned: Debian amavisd-new at rit.se
#  Message-ID: <49A51DB9.8000905@avisita.com>
#  To: "conference@avisita.com >> conference" <conference@avisita.com>
#  Organization: Avisita Travel AB
#  X-Spam-Score: -2.498
#  From: Anne-Louise Larsson <anne-louise.larsson@avisita.com>
#
#  ',
#            ')
#  ',
#            '42 OK FETCH completed.
#  '
#          ];


    my $headers = ""; # original string
    my $msgid;
    my $h = 0;   # in header

    foreach my $header (map {split /\r?\n/} @$raw)
    {
	# little problem: Windows2003 has UID as body, not in header
        if(
	   $header =~ s/^\* \s+ (\d+) \s+ FETCH \s+
                        \( (.*?) BODY\[.*?HEADER (?:\.FIELDS)? .*? \]\s*//ix)
        {
	    # start new message header
            ($msgid, my $msgattrs) = ($1, $2);
	    $h = 1;
            $msgid = $msgattrs =~ m/\b UID \s+ (\d+)/x ? $1 : undef;
        }

        $header =~ /\S/ or next; # skip empty lines.

        # ( for vi
        if($header =~ /^\)/)  # end of this message
        {
	    $h = 0; # inbetween headers
            next;
        }
        elsif(!$msgid && $header =~ /^\s*UID\s+(\d+)\s*\)/)
        {
	    $h = 0;
            next;
        }

        unless( $h )
        {
	    last if $header =~ / OK /i;
            debug(2, "found data between fetch headers: $header");
            next;
        }

	$headers .= $header . "\n";
    }

    return $class->new( \$headers );
}


##############################################################################

1;
