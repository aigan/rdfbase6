#  $Id$  -*-cperl-*-
package Rit::Base::Email::RB::Head;
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

Rit::Base::Email::RB::Head

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
#use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
#use Para::Frame::Utils qw( throw debug idn_encode idn_decode datadump catch fqdn );
use Para::Frame::Utils qw( throw debug );
#use Para::Frame::L10N qw( loc );

use Rit::Base;
use Rit::Base::List;
use Rit::Base::Utils qw( parse_propargs is_undef );
#use Rit::Base::Constants qw( $C_email );
#use Rit::Base::Literal::String;
#use Rit::Base::Literal::Time qw( now ); #);
#use Rit::Base::Literal::Email::Address;
#use Rit::Base::Literal::Email::Subject;

# use constant EA => 'Rit::Base::Literal::Email::Address';

use base qw( Rit::Base::Email::Head );


#######################################################################

=head2 new_by_email

=cut

sub new_by_email
{
    my( $class, $email ) = @_;

    my $head = $class->new("");

    $email->initiate_rel;

    $head->header_set('subject', $email->list('email_subject')->as_array);
    $head->header_set('date', $email->list('email_sent')->as_array);
    $head->header_set('from', $email->list('email_from')->as_array);
    $head->header_set('bcc', $email->list('email_bcc')->as_array);
    $head->header_set('reply-to', $email->list('email_reply_to')->as_array);


    my @to_list = $email->list('email_to')->as_array;
    my $to_obj_list = $email->list('email_to_obj');
    while( my $to_obj = $to_obj_list->get_next_nos )
    {
	push @to_list, $to_obj->email_main->plain;
    }
    $head->header_set('to', @to_list );

    debug "Creating TO header field with @to_list";

    return $head;
}


#######################################################################

1;
