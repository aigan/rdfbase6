#  $Id$  -*-cperl-*-
package Rit::Base::Email::RB;
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

Rit::Base::Email::RB

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
#use URI;
#use MIME::Words qw( decode_mimewords );
#use IMAP::BodyStructure;
#use MIME::QuotedPrint qw(decode_qp);
#use MIME::Base64 qw( decode_base64 );
#use MIME::Types;
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
#use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch fqdn );
use Para::Frame::Utils qw( throw debug );
#use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs alfanum_to_id is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::Head;
use Rit::Base::Email::Classifier::Bounce;
use Rit::Base::Email::Classifier::Vacation;

use constant EA => 'Rit::Base::Literal::Email::Address';

use base qw( Rit::Base::Email::RB::Part );

#######################################################################

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


#######################################################################

=head2 head

  $entity->head()

Returns: The L<Rit::Base::Email::RB::Head> object

=cut

sub head
{
    return $_[0]->{'head'} ||=
      Rit::Base::Email::RB::Head->
	  new_by_email( $_[0]->{'email'} );
}


#######################################################################

=head2 header

  $email->header( $field_name )

Returns: An array ref

=cut

sub header
{
    return([ $_[0]->head->header($_[1]) ]);
}


#######################################################################

=head2 body

=cut

sub body
{
    return $_[0]->email->prop('email_body');
}


#######################################################################

=head2 body_as_html

=cut

sub body_as_html
{
    my( $part ) = @_;

    my $data = CGI->escapeHTML($part->{'email'}->prop('email_body'));
    $data =~ s/\n/<br>\n/g;
    return $data;
}


#######################################################################

1;
