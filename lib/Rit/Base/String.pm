#  $Id$  -*-cperl-*-
package Rit::Base::String;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal String class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::String

=cut

use strict;
use utf8;
use Carp qw( cluck confess );
use Digest::MD5 qw( md5_base64 );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use Rit::Base::Utils qw( is_undef valclean truncstring);

use base qw( Rit::Base::Literal );


use overload
  'cmp'  => 'cmp_string',
  '<=>'  => 'cmp_numeric',
  '0+'   => sub{+($_[0]->{'value'})},
  '+'    => sub{$_[0]->{'value'} + $_[1]},
  ;

=head1 DESCRIPTION

Represents a String L<Rit::Base::Literal>.

=cut


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

=head3 new

=cut

sub new
{
    my( $this, $in_value ) = @_;

    unless( defined $in_value )
    {
	return new Rit::Base::Undef;
    }
    confess "Got a ref to value: $in_value\n" if ref $in_value;

    my $class = ref($this) || $this;

    my $value =
    {
	'arc' => undef,
    };

    if( ref $in_value )
    {
	$value->{'value'} = $$in_value;
    }
    else
    {
	$value->{'value'} = $in_value;
    }

    if( $value->{'value'} =~ /Ã/ )
    {
	confess "HANDLE THIS";
    }
    else
    {
	utf8::upgrade( $value->{'value'} );
    }

#    debug "Created string $value->{'value'}";

    return bless $value, $class;
}


#######################################################################

=head3 new_if_length

=cut

sub new_if_length
{
    my( $this, $in_value ) = @_;

    if( length $in_value )
    {
	return $this->new($in_value);
    }
    else
    {
	return new Rit::Base::Undef;
    }
}


#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

#######################################################################

=head2 desig

  $n->desig()

The designation of the literal

=cut

sub desig  # The designation of obj, meant for human admins
{
    my( $val ) = @_;

    return $val->{'value'};
}


#######################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id.

=cut

sub sysdesig  # The designation of obj, including node id
{
    my $value  = truncstring( shift->{'value'} );
    return "Literal '$value'";
}


#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("lit:%s", md5_base64(shift->{'value'}));
}


#######################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.  This asumes that the
object is a value node or a list of value nodes.

=cut

sub literal
{
#    warn "\t\t\t${$_[0]}\n";
    return $_[0]->{'value'};
}


#######################################################################

=head2 cmp_string

=cut

sub cmp_string
{
    my $val = "";
    if( ref $_[1] )
    {
	if( $_[1]->defined )
	{
	    $val = $_[1]->desig;
	}
    }
    else
    {
	if( defined $_[1] )
	{
	    $val = $_[1];
	}
    }

    if( $_[2] )
    {
	return $val cmp $_[0]->{'value'};
    }
    else
    {
	return $_[0]->{'value'} cmp $val;
    }
}


#######################################################################

=head2 cmp_numeric

=cut

sub cmp_numeric
{
    my $val = 0;
    if( ref $_[1] )
    {
	if( $_[1]->defined )
	{
	    $val = $_[1]->desig;
	}
    }
    else
    {
	if( defined $_[1] )
	{
	    $val = $_[1];
	}
    }

    if( $_[2] )
    {
	return( $val <=> ($_[0]->{'value'}||0));
    }
    else
    {
	return( ($_[0]->{'value'}||0) <=> $val );
    }
}


#######################################################################

=head3 loc

  $lit->loc

  $lit->loc(@args)

Return the value, since only one exists.

Uses the args in L<Para::Frame::L10N/compile>.

=cut

sub loc
{
    my $lit = shift;

    if( @_ )
    {
	my $str = $lit->{'value'};
	my $lh = $Para::Frame::REQ->language;
	my $mt = $lit->{'maketext'} ||= $lh->_compile($str);
	return $lh->compute($mt, \$str, @_);
    }
    else
    {
	my $str = $lit->{'value'};
	if( utf8::is_utf8( $str ) )
	{
	    # Good...
#	    my $len1 = length($str);
#	    my $len2 = bytes::length($str);
#	    debug sprintf "Returning %s(%d/%d):\n", $str, $len1, $len2;
	}
	else
	{
	    debug "String '$str' not marked as UTF8; upgrading";
	    utf8::upgrade($str);
	}
	return $str;
    }
}


#######################################################################

=head3 value

aka literal

=cut

sub value
{
    warn "About to confess...\n";
    confess "wrong turn";
    return $_[0]->{'value'};
}


#######################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

=cut

sub plain
{
    return $_[0]->{'value'};
}


#######################################################################

=head3 clean

Returns the clean version of the value as a Literal obj

=cut

sub clean
{
    return $_[0]->new( valclean( $_[0]->{'value'} ) );
}


#######################################################################

=head3 begins

  $string->begins( $substr )

Returns true if the string begins with $substr.

=cut

sub begins
{
    return $_[0]->{'value'} =~ /^$_[1]/;
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
