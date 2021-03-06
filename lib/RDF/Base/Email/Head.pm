package RDF::Base::Email::Head;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::Head

=head1 DESCRIPTION

The 'to' header may be initialized on demand for cases of really large
lists.

=cut

use 5.014;
use warnings;
use utf8;
use base qw( Email::Simple::Header );
use constant EA => 'RDF::Base::Email::Address';

use Carp qw( croak confess cluck );
use URI;
#use MIME::Words qw( decode_mimewords );
use MIME::WordDecoder qw( mime_to_perl_string );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug idn_encode idn_decode datadump catch fqdn validate_utf8 );
use Para::Frame::L10N qw( loc );

use RDF::Base;
use RDF::Base::List;
use RDF::Base::Utils qw( parse_propargs is_undef );
use RDF::Base::Constants qw( $C_email $C_text );
use RDF::Base::Literal::String;
use RDF::Base::Literal::Time qw( now ); #);
use RDF::Base::Literal::Email::Address;
use RDF::Base::Literal::Email::Subject;




##############################################################################

=head2 as_html

  $header->as_html

=cut

sub as_html
{
    my( $header ) = @_;

    my $msg = "\n<br>\n<table class=\"admin\" style=\"background:#E0E0EA\">\n";

#    debug "HEADERS:\n".datadump($header);

    $header->load_all if $header->can('load_all');

    my @headers = $header->header_pairs;
    for (my $i=0; $i<= $#headers; $i+=2 )
    {
        my( $key ) = $headers[$i];
        my( $val ) = $header->parsed_field($key, $headers[$i+1])->as_html;
        $msg .= "<tr><td style=\"text-align:right;font-weight:bold;vertical-align:top\">$key</td><td>$val</td></tr>\n";
    }
    $msg .= "</table>\n";

    return $msg;
}


##############################################################################

=head2 parsed_field

  $header->parsed_field( $field_name )

  $header->parsed_field( $field_name, $field_value )

Returns: Some sort of L<RDF::Base::Object>. Usually a L<RDF::Base::Literal>

=cut

sub parsed_field
{
    my( $header, $field_in, $value ) = @_;

    my $field = lc($field_in||'');

#    debug "  parsing field '$field'";

    if ( $field eq 'subject' )
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
    elsif ( $field eq "date" )
    {
        return $header->parsed_date($field, $value);
    }
    elsif ( $field eq "from" )
    {
        return $header->parsed_address($field, $value);
    }
    elsif ( $field eq "sender" )
    {
        return $header->parsed_address($field, $value);
    }
    elsif ( $field eq "to" )
    {
        return $header->parsed_address($field, $value);
    }
    elsif ( $field eq "bcc" )
    {
        return $header->parsed_address($field, $value);
    }
    elsif ( $field eq "cc" )
    {
        return $header->parsed_address($field, $value);
    }
    elsif ( $field eq "reply-to" )
    {
        return $header->parsed_address($field, $value);
    }
    elsif ( $field eq "content-description" )
    {
        return $header->parsed_text($field, $value);
    }
    else
    {
        return $header->parsed_default($field, $value);
    }
}


##############################################################################

=head2 parsed_subject

  $header->parsed_subject( $field_name )

  $header->parsed_subject( $field_name, $field_value )

C<$field_name> defaults to C<subject>

C<$field_value> defaults to the first value of C<$field_name>.

Returns: A L<RDF::Base::Literal::Email::Subject>

=cut

sub parsed_subject
{
    my( $header, $field_in, $value ) = @_;

    $field_in ||= 'subject';
    $value ||= $header->header($field_in);
    return $Para::Frame::CFG->{'email_subject_class'}->
      new_by_raw($value);
}


##############################################################################

=head2 parsed_date

  $header->parsed_date()

  $header->parsed_date( $field_name )

  $header->parsed_date( $field_name, $field_value )

C<$field_name> defaults to C<date>.

C<$field_value> defaults to the first value of C<$field_name>.

Returns: A L<RDF::Base::Literal::Time>

=cut

sub parsed_date
{
    my( $header, $field_in, $value ) = @_;

    $field_in ||= 'date';
    $value ||= $header->header($field_in);
    my $date;

    eval
    {
        $date = RDF::Base::Literal::Time->get( $value );
    };
    if ( $@ )
    {
        debug $@;
        $date = is_undef;
    }

    return $date;
}


##############################################################################

=head2 parsed_address

  $header->parsed_address( $field_name )

  $header->parsed_address( $field_name, $field_value )

  $header->parsed_address( $field_name, \@field_values )

C<$field_name> must be given if the values is to be looked up

Returns: a L<RDF::Base::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub parsed_address
{
    my( $header, $field_in, $value ) = @_;

    if ( not $value )
    {
        unless( $field_in )
        {
            confess "missing field name";
        }

        $header->init_to if $field_in eq 'to';
        $value = [ $header->header($field_in) ];
    }
    elsif ( not( ref($value) eq 'ARRAY' ) )
    {
        $value = [$value];
    }

    my @addr;
    foreach my $raw ( @$value )
    {
        my $dec = mime_to_perl_string( $raw );
        push @addr, EA->parse($dec);
    }

#    debug "Got addr list ".join('/',@addr);

    return RDF::Base::List->new(\@addr);
}


##############################################################################

=head2 parsed_default

  $header->parsed_default( $field_name, $field_value )

C<$field_name> and C<$field_value> B<MUST> be given

Returns: a L<RDF::Base::Literal::String>

=cut

sub parsed_default
{
    my( $header, $field_in, $value ) = @_;

    if ( not defined $value )
    {
        confess "missing field value";
    }
    elsif ( ref($value) eq 'ARRAY' )
    {
        croak "field value must be a plain string";
    }

    return RDF::Base::Literal::String->new_from_db($value, $C_text);
}


##############################################################################

=head2 parsed_text

  $header->parsed_text( $field_name, $field_value )

C<$field_name> and C<$field_value> B<MUST> be given

Returns: a L<RDF::Base::Literal::String>

=cut

sub parsed_text
{
    my( $header, $field_in, $value ) = @_;

    if ( not defined $value )
    {
        confess "missing field value";
    }
    elsif ( ref($value) eq 'ARRAY' )
    {
        croak "field value must be a plain string";
    }

    my $dec = mime_to_perl_string( $value );

    return RDF::Base::Literal::String->new_from_db($dec, $C_text);
}


##############################################################################

=head2 init_to

=cut

sub init_to
{
    return 1;
}


##############################################################################

=head2 count_to

=cut

sub count_to
{
    $_[0]->init_to();
    return scalar @{[$_[0]->header('to')]};
}


##############################################################################

=head2 create

  $class->create({ key => [ val1, val2, ...], ... })

Using L<Email::Simple::Creator>

=cut

sub create
{
    my( $class, $hashref ) = @_;

    my $HC = 'Email::Simple::Creator';

    my $header = "";

    foreach my $h ( keys %$hashref )
    {
        foreach my $v ( @{$hashref->{$h}} )
        {
            $HC->_add_to_header( \$header, $h, $v);
        }
    }

    $HC->_finalize_header( \$header );

    return $class->new( \$header );
}

##############################################################################

1;
