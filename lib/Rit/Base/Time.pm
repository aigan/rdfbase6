#  $Id$  -*-cperl-*-
package Rit::Base::Time;

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

use base qw( Para::Frame::Time Rit::Base::Literal );


=head1 DESCRIPTION

Subclass of L<Para::Frame::Time> and L<Rit::Base::Literal>.

=cut

# use overload
#     '0+'   => sub{+($_[0]->{'value'})},
#     '+'    => sub{$_[0]->{'value'} + $_[1]},
#   ;


sub literal
{
    my $str = $_[0]->format_datetime;
    return $str;
}


# Exported via Para::Frame::Time
#
sub now
{
#    carp "Rit::Base::Time::now called";
    return bless(DateTime->now,'Rit::Base::Time')->init;
}

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Para::Frame::Time>

=cut
