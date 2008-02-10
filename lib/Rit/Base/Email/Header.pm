#  $Id$  -*-cperl-*-
package Rit::Base::Email::Header;
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

Rit::Base::Email::Header

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

use base qw( Email::Simple::Header );


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

=head2 as_html

  $header->as_html

=cut

sub as_html
{
    my( $header ) = @_;

    my $msg = "\n<br>\n<table class=\"admin\" style=\"background:#E0E0EA\">\n";

    my @headers = $header->header_pairs;
    for(my $i=0; $i<= $#headers; $i+=2 )
    {
	my( $key ) = $headers[$i];
	my( $val ) = $header->parsed_field($key, $headers[$i+1])->as_html;
	$msg .= "<tr><td style=\"text-align:right;font-weight:bold\">$key</td><td>$val</td></tr>\n";
    }
    $msg .= "</table>\n";

    return $msg;
}


#######################################################################

=head2 parsed_field

  $header->parsed_field( $field_name )

  $header->parsed_field( $field_name, $field_value )

Returns: Some sort of L<Rit::Base::Object>. Usually a L<Rit::Base::Literal>

=cut

sub parsed_field
{
    my( $header, $field_in, $value ) = @_;

    my $field = lc($field_in);

    if( $field eq 'subject' )
    {
	return $header->parsed_subject($field, $value);
    }
#    elsif( $field eq "message-id" )
#    {
#	return $header->parsed_message_id($field, $value);
#    }
#    elsif( $field eq "in-reply-to" )
#    {
#	return $header->parsed_message_id($field, $value);
#    }
#    elsif( $field eq "references" )
#    {
#	return $header->parsed_message_id($field, $value);
#    }
    elsif( $field eq "date" )
    {
	return $header->parsed_date($field, $value);
    }
    elsif( $field eq "from" )
    {
	return $header->parsed_address($field, $value);
    }
    elsif( $field eq "sender" )
    {
	return $header->parsed_address($field, $value);
    }
    elsif( $field eq "to" )
    {
	return $header->parsed_address($field, $value);
    }
    elsif( $field eq "bcc" )
    {
	return $header->parsed_address($field, $value);
    }
    elsif( $field eq "cc" )
    {
	return $header->parsed_address($field, $value);
    }
    elsif( $field eq "reply-to" )
    {
	return $header->parsed_address($field, $value);
    }
    else
    {
	return $header->parsed_default($field, $value);
    }
}


#######################################################################

=head2 parsed_subject

  $header->parsed_subject( $field_name )

  $header->parsed_subject( $field_name, $field_value )

C<$field_name> defaults to C<subject>

C<$field_value> defaults to the first value of C<$field_name>.

Returns: A L<Rit::Base::Literal::Email::Subject>

=cut

sub parsed_subject
{
    my( $header, $field_in, $value ) = @_;

    $field_in ||= 'subject';
    $value ||= $header->header($field_in);
    return $Para::Frame::CFG->{'email_subject_class'}->
      new_by_raw($value);
}


#######################################################################

=head2 parsed_date

  $header->parsed_date()

  $header->parsed_date( $field_name )

  $header->parsed_date( $field_name, $field_value )

C<$field_name> defaults to C<date>.

C<$field_value> defaults to the first value of C<$field_name>.

Returns: A L<Rit::Base::Literal::Time>

=cut

sub parsed_date
{
    my( $header, $field_in, $value ) = @_;

    $field_in ||= 'date';
    $value ||= $header->header($field_in);
    my $date;

    eval
    {
	$date = Rit::Base::Literal::Time->get( $value );
    };
    if( $@ )
    {
	debug $@;
	$date = is_undef;
    }

    return $date;
}


#######################################################################

=head2 parsed_address

  $header->parsed_address( $field_name )

  $header->parsed_address( $field_name, $field_value )

  $header->parsed_address( $field_name, \@field_values )

C<$field_name> must be given if the values is to be looked up

Returns: a L<Rit::Base::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub parsed_address
{
    my( $header, $field_in, $value ) = @_;

    if( not $value )
    {
	unless( $field_in )
	{
	    croak "missing field name";
	}

	$value = [ $header->header($field_in) ];
    }
    elsif( not( ref($value) eq 'ARRAY' ) )
    {
	$value = [$value];
    }

    my @addr;
    foreach my $raw ( @$value )
    {
	my $dec = decode_mimewords( $raw );
	push @addr, EA->parse_tolerant($dec);
    }

    return Rit::Base::List->new(\@addr);
}


#######################################################################

=head2 parsed_default

  $header->parsed_default( $field_name, $field_value )

C<$field_name> and C<$field_value> B<MUST> be given

Returns: a L<Rit::Base::Literal::String>

=cut

sub parsed_default
{
    my( $header, $field_in, $value ) = @_;

    if( not $value )
    {
	croak "missing field name";
    }
    elsif( ref($value) eq 'ARRAY' )
    {
	croak "field value must be a plain string";
    }

    return Rit::Base::Literal::String->new_from_db($value);
}


#######################################################################

1;
