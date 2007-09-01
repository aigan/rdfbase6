#  $Id$  -*-cperl-*-
package Rit::Base::Literal::Email::Address;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal Email Address class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email::Address

=cut

use strict;
use Carp qw( cluck confess longmess );
use Mail::Address;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Rit::Base::Utils qw( is_undef );

use base qw( Rit::Base::Literal::String Para::Frame::Email::Address );
# Parent overloads some operators!


=head1 DESCRIPTION

Represents an Email Address

=cut


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

=head3 new

Calls L<Para::Frame::Email::Address/parse>

=cut

sub new
{
    my( $class, $in_value ) = @_;

    return $class->Para::Frame::Email::Address::parse($in_value);
}


#######################################################################

=head3 parse

Wrapper for L<Para::Frame::Email::Address/parse> that reimplements
L<Rit::Base::Literal::String/parse>. (Avoid recursion)

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);


    if( ref $val eq 'SCALAR' )
    {
	return $class->Para::Frame::Email::Address::parse($$val);
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::Email::Address" )
    {
	return $val;
    }
    elsif( UNIVERSAL::isa $val, "Para::Frame::Email::Address" )
    {
	return bless $val, $class;
    }
    elsif( UNIVERSAL::isa $val, "Mail::Address" )
    {
	return $class->Para::Frame::Email::Address::parse($val);
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Undef" )
    {
	confess "Implement undef addresses";
    }
    else
    {
	confess "Can't parse $val";
    }
}


#######################################################################

=head3 new_from_db

Assumes that the value from DB is correct

=cut

sub new_from_db
{
    my( $class, $val ) = @_;

    my( $addr ) = Mail::Address->parse( $val );
    return bless { addr => $addr }, $class;
}


#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

#######################################################################

=head2 sysdesig

  $a->sysdesig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub sysdesig
{
    my $value  = shift->format;
    return "email_address:$value";
}


#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return shift->sysdesig;
}


#######################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.  This asumes that the
object is a value node or a list of value nodes.

=cut

sub literal
{
    return $_[0]->format;
}


#######################################################################

=head3 loc

  $lit->loc

Just returns the plain string

=cut

sub loc
{
    return shift->plain;
}


#######################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

=cut

sub plain
{
    return $_[0]->format;
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
