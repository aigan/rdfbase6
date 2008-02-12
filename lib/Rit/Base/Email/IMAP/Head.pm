#  $Id$  -*-cperl-*-
package Rit::Base::Email::IMAP::Head;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email::IMAP::Head

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use URI;
use MIME::Words qw( decode_mimewords );
use IMAP::BodyStructure;
use MIME::QuotedPrint qw(decode_qp);
use MIME::Base64 qw( decode_base64 );
use MIME::Types;
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug idn_encode idn_decode datadump catch fqdn );
use Para::Frame::L10N qw( loc );

use Rit::Base;
use Rit::Base::List;
use Rit::Base::Utils qw( parse_propargs is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;

use constant EA => 'Rit::Base::Literal::Email::Address';

use base qw( Rit::Base::Email::Head );


#######################################################################

=head2 new_by_uid

Taken from L<Mail::IMAPClient/parse_headers>

=cut

sub new_by_uid
{
    my( $class, $folder, $uid ) = @_;

    my $raw = $folder->imap_cmd('fetch',
				"$uid BODY.PEEK[HEADER]");

    my $headers; # original string
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
            debug(0, "found data between fetch headers: $header");
            next;
        }

	$headers .= $header . "\n";
    }

    return $class->new( \$headers );
}


#######################################################################

=head2 new_by_part_env

Takes a IMAP::BodyStructure::Envelope

=cut

sub new_by_part_env
{
    my( $class, $env ) = @_;

    my $head = $class->new("");

    $head->header_set('date', $env->{date} ); ### CHECKME
    $head->header_set('subject', $env->{subject} );
    $head->header_set('message-id', $env->{message_id} );
    $head->header_set('in-reply-to', $env->{in_reply_to} );
    $head->header_set('to', map $_->{full}, @{$env->{to}} );
    $head->header_set('from', map $_->{full}, @{$env->{from}} );
    $head->header_set('cc', map $_->{full}, @{$env->{cc}} );
    $head->header_set('bcc', map $_->{full}, @{$env->{bcc}} );
    $head->header_set('sender', map $_->{full}, @{$env->{sender}} );
    $head->header_set('reply-to', map $_->{full}, @{$env->{reply_to}} );

    return $head;
}


#######################################################################

1;
