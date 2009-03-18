package Rit::Base::Email::Interpart;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email::Interpart

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( Rit::Base::Email::Part );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;


#######################################################################

=head2 new

=cut

sub new
{
    my( $part, $child ) = @_;

    my $class = ref($part) or die "Must be called by parent";

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     parent => $part,
     type   => 'message/rfc822',
     child  => $child,
    }, 'Rit::Base::Email::Interpart';

    weaken( $sub->{'email'} );
    weaken( $sub->{'parent'} );
#    weaken( $sub->{'top'} );

#    debug datadump($struct);

    $child->{'parent'} = $sub;

    return $sub;


}


#######################################################################

=head2 body_head

See L<Rit::Base::Email::Part/body_head>

=cut

sub body_head
{
    return $_[0]->{'child'}->head;
}


#######################################################################

=head2 body_part

See L<Rit::Base::Email::IMAP/body_part>

=cut

sub body_part
{
    return $_[0]->{'child'};
}


#######################################################################

=head2 path

See L<Rit::Base::Email::Part/path>

=cut

sub path
{
    $_[0]->{'child'}->path;
}


#######################################################################

=head2 type

See L<Rit::Base::Email::Part/type>

=cut

sub type
{
    return $_[0]->{'type'};
}


#######################################################################

1;
