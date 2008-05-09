#  $Id$  -*-cperl-*-
package Rit::Base::Email::RB::Part;
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

Rit::Base::Email::RB::Part

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
use Para::Frame::Utils qw( throw debug );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs is_undef );
use Rit::Base::Email::Head;

use base qw( Rit::Base::Email::Part );

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

=head2 folder

RB emails has no folder. We define this method in case it's called
from a TT form...

Returns: undef

=cut

sub folder
{
    return undef;
}


#######################################################################

1;
