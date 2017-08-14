package RDF::Base::Email::RB;
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

RDF::Base::Email::RB

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;
use base qw( RDF::Base::Email::RB::Part );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
#use CGI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use RDF::Base;
use RDF::Base::Literal::String;
use RDF::Base::Email::Head;


##############################################################################

=head2 new_by_email

=cut

sub new_by_email
{
    my( $class, $email ) = @_;

    my $entity = bless
    {
     email => $email,
    }, $class;
    weaken( $entity->{'email'} );

    return $entity;
}


##############################################################################

=head2 head_complete

  $entity->head_complete()

Returns: The L<RDF::Base::Email::RB::Head> object

=cut

sub head_complete
{
    return $_[0]->{'head'} ||=
      RDF::Base::Email::RB::Head->
	  new_by_email( $_[0]->{'email'} );
}


##############################################################################

=head2 body_raw

Returns a scalar ref

=cut

sub body_raw
{
    my( $part ) = @_;

    if( my $raw = $part->email->first_prop('email_body')->plain )
    {
	return \ $raw;
    }
    elsif( my $tmple = $part->email->first_prop
	   ('has_email_body_template_email') )
    {
	my $tmpleo = $part->{'template_email_obj'} ||=
	  RDF::Base::Email::IMAP->new_by_email( $tmple );

	debug "Getting raw body of ".$tmpleo->sysdesig;
	debug "That has path ".$tmpleo->path;
	return $tmpleo->body_raw;
    }

    return \ undef;
}


##############################################################################

=head2 body_as_html

=cut

sub body_as_html
{
    my( $part, $args ) = @_;

    if( my $raw = $part->email->first_prop('email_body') )
    {
	my $data = CGI->escapeHTML( $raw );
	$data =~ s/\n/<br>\n/g;
	return $data;
    }
    elsif( my $tmple = $part->email->first_prop
	   ('has_email_body_template_email') )
    {
	my $tmpleo = $part->{'template_email_obj'} ||=
	  RDF::Base::Email::IMAP->new_by_email( $tmple );
	return $tmpleo->body_as_html($args);
    }

    return "";
}


##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $part ) = @_;

    return($part->head->parsed_subject->plain || '<no subject>');
}


##############################################################################

=head2 is_top

=cut

sub is_top
{
    return 1;
}


##############################################################################

=head2 type

=cut

sub type
{
    return 'text/plain';
}


##############################################################################

=head2 parts

=cut

sub parts
{
    return ();
}


##############################################################################

=head2 encoding

=cut

sub encoding
{
    return 'binary';
}


##############################################################################

=head2 charset

=cut

sub charset
{
    return 'iso-8859-1'; # Internal format
}


##############################################################################

1;
