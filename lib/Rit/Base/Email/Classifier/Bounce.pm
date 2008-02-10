#  $Id$  -*-cperl-*-
package Rit::Base::Email::Classifier::Bounce;
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

Rit::Base::Email::Classifier::Bounce

=cut

use strict;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );

#use Rit::Base::Constants qw( $C_email );

=head1 DESCRIPTION

Based on L<Mail::DeliveryStatus::BounceParser>

=cut


#######################################################################

=head2 new

=cut

sub new
{
    my( $this, $email ) = @_;
    my $class = ref($this) || $this;

    my $bounce = bless
    {
     email => $email,
     reports => [],
     is_bounce => 0,
     orig_message_id => undef,
     format => undef,
    }, $class;
    weaken( $bounce->{'email'} );

    $bounce->analyze;

    return $bounce;
}


#######################################################################

=head2 is_bounce

=cut

sub is_bounce
{
    my( $bounce ) = @_;

    return $bounce->{'is_bounce'} ? 1 : 0;
}


#######################################################################

=head2 analyze

=cut

sub analyze
{
    my( $bounce ) = @_;

    my $email = $bounce->{'email'};

    debug "Starting analyzing message ".$email->desig;

    if( $email->is_message_challenge_response )
    {
	return;
    }

#    ### Check format
#    $bounce->p_ims;              # Internet Mail Service
#    $bounce->p_aol_senderblock;  # AirMail
#    $bounce->p_novell_groupwise; # Novell Groupwise
#    $bounce->p_plain_smtp_transcript;
#    $bounce->p_xdelivery_status;


    return 1;
}


#######################################################################

1;
