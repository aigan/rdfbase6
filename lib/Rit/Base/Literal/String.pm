#  $Id$  -*-cperl-*-
package Rit::Base::Literal::String;
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

Rit::Base::Literal::String

=cut

use strict;
use utf8;

use Carp qw( cluck confess longmess );
use Digest::MD5 qw( md5_base64 );
use Scalar::Util qw( looks_like_number );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug trim throw );

use Rit::Base::Utils qw( is_undef valclean truncstring query_desig );

use base qw( Rit::Base::Literal );


use overload
  'cmp'  => 'cmp_string',
  '<=>'  => 'cmp_numeric',
  '0+'   => sub{+($_[0]->literal)},
  '+'    => sub{$_[0]->literal + $_[1]},
  fallback => 1,
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
    my $class = ref($this) || $this;

    unless( defined $in_value )
    {
	return bless
	{
	 'arc' => undef,
	 'value' => undef,
	}, $class;
    }

    my $val; # The actual string
    if( ref $in_value )
    {
	if( ref $in_value eq 'SCALAR' )
	{
	    $val = $$in_value;
	}
	else
	{
	    confess "Invalid value: $in_value";
	}
    }
    else
    {
	$val = $in_value;
    }

    if( utf8::is_utf8($val) )
    {
	if( utf8::valid($val) )
	{
	    if( $val =~ /Ã./ )
	    {
		debug longmess "Value '$val' DOUBLE ENCODED!!!";
		$Para::Frame::REQ->result->message("Some text double encoded!");
	    }
	}
	else
	{
	    confess "Value '$val' marked as INVALID utf8";
	}
    }
    else
    {
	if( $val =~ /Ã./ )
	{
	    debug "HANDLE THIS (apparent undecoded UTF8: $val)";
	    unless( utf8::decode( $val ) )
	    {
		$Para::Frame::REQ->result->message("Failed to convert to UTF8!");
	    }
	}
	else
	{
	    utf8::upgrade( $val );
	}
    }

#    debug "Created string $value->{'value'}";


    return bless
    {
     'arc' => undef,
     'value' => $val,
    }, $class;
}


#######################################################################

=head3 new_from_db

=cut

sub new_from_db
{
    my( $class, $val ) = @_;

    if( defined $val )
    {
	if( $val =~ /Ã./ )
	{
	    debug "UNDECODED UTF8 in DB: $val)";
	    unless( utf8::decode( $val ) )
	    {
		$Para::Frame::REQ->result->message("Failed to convert to UTF8!");
	    }
	}
	else
	{
	    utf8::upgrade( $val );
	}
    }

    return bless
    {
     'arc' => undef,
     'value' => $val,
    }, $class;
}


#######################################################################

=head3 parse

  $class->parse( \$value, \%args )

For parsing any type of input. Expecially as given by html forms.

Supported args are:
  valtype
  coltype
  arclim

Will use L<Rit::Base::Resource/get_by_anything> for lists and queries.

The valtype may be given for cases there the class handles several
valtypes.

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    if( $coltype eq 'obj' ) # Is this a value node?
    {
	if( $valtype )
	{
	    $coltype = $valtype->coltype;
	}

	debug "Parsing as $coltype: ".query_desig($val_in);
    }


    if( ref $val eq 'SCALAR' )
    {
	if( $coltype eq 'valtext' )
	{
	    return $class->new($val);
	}
	elsif( $coltype eq 'valfloat' )
	{
	    trim($val);
	    unless( looks_like_number( $$val ) )
	    {
		throw 'validation', "String $$val is not a number";
	    }
	    return $class->new($val);
	}
	else
	{
	    confess "coltype $coltype not handled by this class";
	}
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
    {
	# Still parsing it
	if( $coltype eq 'valfloat' )
	{
	    unless( looks_like_number( $val->plain ) )
	    {
		throw 'validation', "String $val is not a number";
	    }
	}

	return $val;
    }
    else
    {
	confess "Can't parse $val";
    }
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
    if( defined $_[0]->{'value'} )
    {
	my $value  = truncstring( shift->{'value'} );
	return "Literal '$value'";
    }
    else
    {
	return "Literal undef";
    }
}


#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    if( defined $_[0]->{'value'} )
    {
	if( utf8::is_utf8( $_[0]->{'value'} ) )
	{
	    my $encoded = $_[0]->{'value'};
	    utf8::encode( $encoded );
	    return sprintf("lit:%s", md5_base64($encoded));
	}
	return sprintf("lit:%s", md5_base64(shift->{'value'}));
    }
    else
    {
	return "lit:undef";
    }
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
    my $val1 = $_[0]->plain;
    my $val2 = $_[1];

    unless( defined $val1 )
    {
	$val1 = is_undef;
    }

    if( ref $val2 )
    {
	if( $val2->defined )
	{
	    $val2 = $val2->desig;
	}
    }
    else
    {
	unless( defined $val2 )
	{
	    $val2 = is_undef;
	}
    }

    if( $_[2] )
    {
	return $val2 cmp $val1;
    }
    else
    {
	return $val1 cmp $val2;
    }
}


#######################################################################

=head2 cmp_numeric

=cut

sub cmp_numeric
{
    my $val1 = $_[0]->plain || 0;
    my $val2 = $_[1]        || 0;

    unless( defined $val1 )
    {
	$val1 = is_undef;
    }

    if( ref $val2 )
    {
	if( $val2->defined )
	{
	    $val2 = $val2->desig;
	}
	else
	{
	    $val2 = 0;
	}
    }

    if( $_[2] )
    {
	return( $val2 <=> $val1 );
    }
    else
    {
	return( $val1 <=> $val2 );
    }
}


#######################################################################

=head3 loc

  $lit->loc

  $lit->loc(@args)

Uses the args in L<Para::Frame::L10N/compile>.

Returns: the value as a plain string

=cut

sub loc
{
    my $lit = shift;

    unless( defined $lit->{'value'} )
    {
	return is_undef;
    }

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

=head3 clean_plain

Returns the clean version of the value as a plain string

=cut

sub clean_plain
{
    return valclean( $_[0]->{'value'} );
}


#######################################################################

=head3 begins

  $string->begins( $substr )

Returns true if the string begins with $substr.

=cut

sub begins
{
    unless( defined $_[0]->{'value'} )
    {
	return is_undef;
    }

    return $_[0]->{'value'} =~ /^$_[1]/;
}

#######################################################################

=head3 coltype

=cut

sub coltype
{
    return "valtext";
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