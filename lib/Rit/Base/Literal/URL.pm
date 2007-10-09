#  $Id$  -*-cperl-*-
package Rit::Base::Literal::URL;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal URL class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::URL

=cut

use strict;
use Carp qw( cluck confess longmess );
use CGI;
use URI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use Rit::Base::Utils qw( );

use base qw( Para::Frame::URI Rit::Base::Literal::String );
# Parent overloads some operators!


=head1 DESCRIPTION

Represents an URL (or URI). This is a wrapper for L<URI> that
redirects calls to that class. It's extended as a
L<Rit::Base::Literal::String>.

=cut


#######################################################################

=head3 new

  $this->new( $value, $valtype )

=cut

sub new
{
    my( $this, $value, $valtype ) = @_;
    my $class = ref $this || $this;

    my $uri = URI->new($value);

    return bless
    {
     value => $uri,
     valtype => $valtype,
    }, $class;
}


#######################################################################

=head3 parse

  $this->parse( $value, $valtype )

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    if( $coltype eq 'obj' ) # Is this a value node?
    {
	$coltype = $valtype->coltype;
	debug "Parsing as $coltype: ".query_desig($val_in);
    }

    my $val_mod;
    if( ref $val eq 'SCALAR' )
    {
	$val_mod = $$val;
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
    {
	$val_mod = $val->plain;
    }
    else
    {
	confess "Can't parse $val";
    }

    unless( length $val_mod )
    {
	$class->new( undef, $valtype );
    }

    # Always return the incoming object. This may MODIFY the object
    #
    if( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
    {
	$val->{'value'} = URI->new($val_mod);
	$val->{'valtype'} = $valtype;
	return $val;
    }

    # Implementing class may not take scalarref
    return $class->new( $val_mod, $valtype );
}


#######################################################################

=head3 new_from_db

  $this->new_from_db( $value, $valtype )

Assumes that the value from DB is correct

=cut

sub new_from_db
{
    my( $this, $value, $valtype ) = @_;
    my $class = ref $this || $this;

    my $uri = URI->new($value);

    return bless
    {
     value => $uri,
     valtype => $valtype,
    }, $class;
}


#######################################################################

=head3 getset

Used by most get/set wrapper methods

Updated the arc

=cut

sub getset
{
    my( $u, $method ) = (shift, shift);
    if( my $uri = $u->{'value'} )
    {
	if( @_ and $u->arc )
	{
	    my $res = $uri->$method(@_);
	    $u->arc->set_value($u->plain);
	    return $res;
	}
	return $uri->$method(@_);
    }

    return "";
}


#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return $_[0]->sysdesig;
}


#######################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.  This asumes that the
object is a value node or a list of value nodes.

=cut

sub literal
{
    return $_[0]->desig;
}


#######################################################################

=head3 loc

  $lit->loc

Just returns the plain string

=cut

sub loc
{
    return $_[0]->desig;
}


#######################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

=cut

sub plain
{
    return $_[0]->desig;
}


#######################################################################

=head3 getset_query

Used by query get/set wrapper methods

Updated the arc

=cut

sub getset_query
{
    my( $u, $method ) = (shift, shift);
    if( my $uri = $u->{'value'} )
    {
	if( (@_>1) and $u->arc )
	{
	    my $res = $uri->$method(@_);
	    $u->arc->set_value($u->plain);
	    return $res;
	}
	return $uri->$method(@_);
    }

    return "";
}


#######################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return Rit::Base::Literal::Class->get_by_label('url');
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
