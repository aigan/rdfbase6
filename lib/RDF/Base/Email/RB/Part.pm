package RDF::Base::Email::RB::Part;
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

RDF::Base::Email::RB::Part

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;
use base qw( RDF::Base::Email::Part );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );
use Para::Frame::List;

use RDF::Base;
use RDF::Base::Utils qw( parse_propargs is_undef );
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

=head2 folder

RB emails has no folder. We define this method in case it's called
from a TT form...

Returns: undef

=cut

sub folder
{
    return undef;
}


##############################################################################

=head2 generate_name

See L<RDF::Base::Email::Part/generate_name>

=cut

sub generate_name
{
    my( $part ) = @_;

    my $name = "email".$part->email->id;
    $name .= "-part".$part->path;
    return $name;
}


##############################################################################

=head2 path

=cut

sub path
{
    return 'E';
}


##############################################################################

=head2 top

=cut

sub top
{
    return $_[0];
}


##############################################################################

1;
