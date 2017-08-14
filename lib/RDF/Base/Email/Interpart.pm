package RDF::Base::Email::Interpart;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::Interpart

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;
use base qw( RDF::Base::Email::Part );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use RDF::Base;
use RDF::Base::Utils qw( parse_propargs is_undef );
use RDF::Base::Constants qw( $C_email );
use RDF::Base::Literal::Email::Address;
use RDF::Base::Literal::Email::Subject;


##############################################################################

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
    }, 'RDF::Base::Email::Interpart';

    weaken( $sub->{'email'} );
    weaken( $sub->{'parent'} );
#    weaken( $sub->{'top'} );

#    debug datadump($struct);

    $child->{'parent'} = $sub;

    return $sub;


}


##############################################################################

=head2 body_head

See L<RDF::Base::Email::Part/body_head>

=cut

sub body_head
{
    return $_[0]->{'child'}->head;
}


##############################################################################

=head2 body_part

See L<RDF::Base::Email::IMAP/body_part>

=cut

sub body_part
{
    return $_[0]->{'child'};
}


##############################################################################

=head2 path

See L<RDF::Base::Email::Part/path>

=cut

sub path
{
    $_[0]->{'child'}->path;
}


##############################################################################

=head2 type

See L<RDF::Base::Email::Part/type>

=cut

sub type
{
    return $_[0]->{'type'};
}


##############################################################################

1;
