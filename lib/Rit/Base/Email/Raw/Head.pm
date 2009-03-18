package Rit::Base::Email::Raw::Head;
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

Rit::Base::Email::RB::Head

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( Rit::Base::Email::Head );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
use List::Uniq qw( uniq ); # keeps first of each value

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );


#######################################################################

=head2 new_by_part

=cut

sub new_by_part
{
    my( $class, $part ) = @_;

    my $head = $part->{'em'}->header_obj;

#    debug datadump($head);

    return bless $head, $class;
}


#######################################################################

1;
