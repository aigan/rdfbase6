#  $Id$  -*-cperl-*-
package Rit::Base::Literal::Time;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal Time class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::Time

=cut

use strict;
use Carp qw( cluck carp confess );
use DateTime::Incomplete;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}


use Para::Frame::Utils qw( throw debug datadump );

use Rit::Base::Utils qw( );

use base qw( Para::Frame::Time Rit::Base::Literal );


=head1 DESCRIPTION

Subclass of L<Para::Frame::Time> and L<Rit::Base::Literal>.

=cut

# use overload
#     '0+'   => sub{+($_[0]->{'value'})},
#     '+'    => sub{$_[0]->{'value'} + $_[1]},
#   ;


#######################################################################

=head2 parse

  $class->parse( \$value, \%args )


Supported args are:
  valtype
  coltype
  arclim

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    if( ref $val eq 'SCALAR' )
    {
	return $class->new($$val, $valtype);
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::Time" )
    {
	return $val;
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
    {
	return $class->new($val->plain, $valtype);
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Undef" )
    {
	return $class->new(undef, $valtype);
    }
    else
    {
	confess "Can't parse $val";
    }
}

#######################################################################

=head2 new_from_db

  $this->new_from_db( $value, $valtype )

=cut

sub new_from_db
{
    # Should parse faster since we know this is a PostgreSQL type
    # timestamp with time zone...

    my $time = $Rit::dbix->parse_datetime($_[1], $_[0])->init;
    $time->{'valtype'} = $_[2];
    return $time;
}

#######################################################################

=head2 new

  $this->new( $time, $valtype )

Extension of L<Para::Frame::Time/get>

=cut

sub new
{
    my $this = shift;

    my( $time, $valtype);
    if( scalar @_ > 2 )
    {
	$time = $this->SUPER::new(@_);
    }
    else
    {
	$time = $this->SUPER::get($_[0]);
	$valtype = $_[1];
    }

    unless( $time )
    {
#	$time = DateTime::Incomplete->new();
#	my $class = ref $this || $this;
#	bless($time, $class)->init;
	use Rit::Base::Undef;
	return Rit::Base::Undef->new(); ### FIXME!
    }

    $time->{'valtype'} = $valtype;

    return $time;
}

#######################################################################

=head2 get

  $this->get( $time, $valtype )

Extension of L<Para::Frame::Time/get>

=cut

sub get
{
    return shift->new(@_);
}

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
#    carp "Rit::Base::Literal::Time::now called";
    return bless(DateTime->now,'Rit::Base::Literal::Time')->init;
}

#######################################################################

=head2 date

=cut

sub date
{
    return bless(Para::Frame::Time->new(@_),'Rit::Base::Literal::Time');
}

#######################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return Rit::Base::Literal::Class->get_by_label('valdate');
}

#######################################################################
#
#=head3 defined
#
#=cut
#
#sub defined
#{
#    if( UNIVERSAL::isa $_[0], 'DateTime::Incomplete' )
#    {
#	if( $_[0]->is_undef )
#	{
#	    return 0;
#	}
#    }
#
#    return 1;
#}
#
#######################################################################
#
#=head2 format_datetime
#
#  $t->format_datetime()
#
#Returns a string using the format given by L<Para::Frame/configure>.
#
#=cut
#
#sub format_datetime
#{
#    if( UNIVERSAL::isa $_[0], 'DateTime::Incomplete' )
#    {
#	if( $_[0]->is_undef )
#	{
#	    return "";
#	}
#	else
#	{
#	    return $_[0]->iso8601;
#	}
#    }
#
#    return $Para::Frame::Time::FORMAT->format_datetime($_[0]);
#}
#
#
#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Para::Frame::Time>

=cut
