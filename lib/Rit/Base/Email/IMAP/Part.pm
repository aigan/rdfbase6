#  $Id$  -*-cperl-*-
package Rit::Base::Email::IMAP::Part;
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

Rit::Base::Email::IMAP::Part

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use base qw( Rit::Base::Email::Part );

#######################################################################

=head2 new

=cut

sub new
{
    my( $part, $struct ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     struct => $struct,
    }, 'Rit::Base::Email::IMAP::Part';

    weaken( $sub->{'email'} );
#    weaken( $sub->{'top'} );

    return $sub;
}


#######################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    my( $part, $path ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    unless( $path )
    {
	return $part;
    }

    my $struct = $part->top->struct->part_at($path);

    unless( $struct )
    {
	debug "Failed to get struct at $path";
	debug "Top: ".$part->top;
	debug "Top struct: ". $part->top->struct;
	debug $part->top->desig;
	confess datadump($part,1);
    }

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     struct => $struct,
    }, 'Rit::Base::Email::IMAP::Part';
    weaken( $sub->{'email'} );
#    weaken( $sub->{'top'} );

    return $sub;
}


#######################################################################

1;
