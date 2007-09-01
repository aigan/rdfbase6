#  $Id$  -*-cperl-*-
package Rit::Base::Time;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal Time class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Time

=cut

use strict;
use Carp qw( cluck carp );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw debug );

use Rit::Base::Utils qw( is_undef );

use base qw( Para::Frame::Time Rit::Base::Literal );


=head1 DESCRIPTION

Subclass of L<Para::Frame::Time> and L<Rit::Base::Literal>.

=cut

# use overload
#     '0+'   => sub{+($_[0]->{'value'})},
#     '+'    => sub{$_[0]->{'value'} + $_[1]},
#   ;


#######################################################################

=head2 literal

=cut

sub literal
{
    my $str = $_[0]->format_datetime;
    return $str;
}

#######################################################################


=head2 now

NOTE: Exported via Para::Frame::Time

=cut

sub now
{
#    carp "Rit::Base::Time::now called";
    return bless(DateTime->now,'Rit::Base::Time')->init;
}

#######################################################################

=head2 date

=cut

sub date
{
    return bless(Para::Frame::Time->get(@_),'Rit::Base::Time');
}

#######################################################################

=head2 get

Extension of L<Para::Frame::Time/get>

=cut

sub get
{
    return shift->SUPER::get(@_) || is_undef;
}

#######################################################################

=head2 new_from_db

=cut

sub new_from_db
{
    # Should parse faster since we know this is a PostgreSQL type
    # timestamp with time zone...

    return $Rit::dbix->parse_datetime($_[1], $_[0]);
}

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Para::Frame::Time>

=cut
