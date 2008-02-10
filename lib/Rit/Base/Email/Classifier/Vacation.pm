#  $Id$  -*-cperl-*-
package Rit::Base::Email::Classifier::Vacation;
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

Rit::Base::Email::Classifier::Vacation

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

    my $vacation = bless
    {
     email => $email,
     is_vacation => 0,
     format => undef,
    }, $class;
    weaken( $vacation->{'email'} );

    $vacation->analyze;

    return $vacation;
}


#######################################################################

=head2 is_vacation

=cut

sub is_vacation
{
    my( $vacation ) = @_;

    return $vacation->{'is_vacation'} ? 1 : 0;
}


#######################################################################

=head2 analyze

=cut

sub analyze
{
    my( $vacation ) = @_;

    my $email = $vacation->{'email'};

    debug "Starting analyzing message ".$email->desig;


    # From Mail::DeliveryStatus::BounceParser:
    #
    # we'll deem autoreplies to be usually less than a certain size.
    #
    # Some vacation autoreplies are (sigh) multipart/mixed, with an
    # additional part containing a pointless disclaimer; some are
    # multipart/alternative, with a pointless HTML part saying the
    # exact same thing.  (Messages in this latter category have the
    # decency to self-identify with things like '<META
    # NAME="Generator" CONTENT="MS Exchange Server version
    # 5.5.2653.12">', so we know to avoid such software in future.)
    # So look at the first part of a multipart message (recursively,
    # down the tree).

#    {
#	# is bounce?
#	last if $email->effective_type_plain eq 'multipart/report';
#
#	last if !$first_part || $first_part->effective_type ne 'text/plain';
#	my $string = $first_part->as_string;
#	last if length($string) > 3000;
#	last if $string !~ /auto.{0,20}reply|vacation|(out|away|on holiday).*office/i;
#	$self->log("looks like a vacation autoreply, ignoring.");
#	$self->{type} = "vacation autoreply";
#	$self->{is_bounce} = 0;
#    }

    return 1;
}


#######################################################################

1;
