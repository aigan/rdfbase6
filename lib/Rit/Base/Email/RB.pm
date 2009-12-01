package Rit::Base::Email::RB;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

=head1 NAME

Rit::Base::Email::RB

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( Rit::Base::Email::RB::Part );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
use CGI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Literal::String;
use Rit::Base::Email::Head;


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

Returns: The L<Rit::Base::Email::RB::Head> object

=cut

sub head_complete
{
    return $_[0]->{'head'} ||=
      Rit::Base::Email::RB::Head->
	  new_by_email( $_[0]->{'email'} );
}


##############################################################################

=head2 body

=cut

sub body
{
    my( $part ) = @_;

    if( my $raw = $part->email->first_prop('email_body') )
    {
	return \ $raw;
    }
    elsif( my $tmple = $part->email->first_prop
	   ('has_email_body_template_email') )
    {
	my $tmpleo = $part->{'template_email_obj'} ||=
	  Rit::Base::Email::IMAP->new_by_email( $tmple );

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
    my( $part ) = @_;

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
	  Rit::Base::Email::IMAP->new_by_email( $tmple );
	return $tmpleo->body_as_html;
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

1;
