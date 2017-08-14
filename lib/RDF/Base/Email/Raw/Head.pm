package RDF::Base::Email::Raw::Head;
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

RDF::Base::Email::RB::Head

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;
use base qw( RDF::Base::Email::Head );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
use List::Uniq qw( uniq ); # keeps first of each value

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );


##############################################################################

=head2 new_by_part

=cut

sub new_by_part
{
    my( $class, $part ) = @_;

    my $head = $part->{'em'}->header_obj;

#    debug datadump($head);

    return bless $head, $class;
}


##############################################################################

1;
