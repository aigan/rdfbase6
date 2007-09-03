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

use Rit::Base::Utils qw( is_undef );

use base qw( Rit::Base::Literal::String );
# Parent overloads some operators!


=head1 DESCRIPTION

Represents an URL (or URI). This is a wrapper for L<URI> that
redirects calls to that class. It's extended as a
L<Rit::Base::Literal::String>.

Methods not encapsulated are:

  as_string : use plain()
  eq        : use equals()

=cut


#######################################################################

=head3 new

Wrapper for L<URI/new>

=cut

sub new
{
    my( $class ) = shift;

    my $uri = URI->new(@_);

    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head3 new_from_db

Assumes that the value from DB is correct

=cut

sub new_from_db
{
    my( $class ) = shift;

    my $uri = URI->new(@_);

    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head2 as_html

  $a->as_html

=cut

sub as_html
{
    my( $url, $label ) = @_;

    return "" unless $url->{'value'};

    my $href = $url->{'value'}->as_string;
    $label ||= $href;

    my $label_out = CGI->escapeHTML($label);
    my $href_out = CGI->escapeHTML($href);

    return "<a href=\"$href_out\">$label_out</a>";
}


#######################################################################

=head2 sysdesig

  $a->sysdesig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub sysdesig
{
    if( my $str = "$_[0]->{value}" )
    {
	return "URL $str";
    }
    else
    {
	return "URL undef";
    }
}


#######################################################################

=head2 desig

  $a->desig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub desig
{
    return "$_[0]->{value}";
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

=head3 new_abs

=cut

sub new_abs
{
    my( $class ) = shift;

    my $uri = URI->new_abs(@_);

    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head3 clone

=cut

sub clone
{
    my $uri = $_[0]->clone;
    my $class = ref $_[0];

    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head3 getset

Used by most get/set wrapper methods

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

=head3 schema

=cut

sub schema
{
    return shift->getset('schema',@_);
}


#######################################################################

=head3 opaque

=cut

sub opaque
{
    return shift->getset('opaque',@_);
}


#######################################################################

=head3 path

=cut

sub path
{
    return shift->getset('path',@_);
}


#######################################################################

=head3 fragment

=cut

sub fragment
{
    return shift->getset('fragment',@_);
}


#######################################################################

=head3 canonical

=cut

sub canonical
{
    my $uri = $_[0]->canonical;

    if( $_[0]->eq( $uri ) )
    {
	return $_[0];
    }

    my $class = ref $_[0];
    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head3 abs

=cut

sub abs
{
    my $uri = $_[0]->abs($_[1]);

    if( $_[0]->eq( $uri ) )
    {
	return $_[0];
    }

    my $class = ref $_[0];
    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head3 rel

=cut

sub rel
{
    my $uri = $_[0]->rel($_[1]);

    if( $_[0]->eq( $uri ) )
    {
	return $_[0];
    }

    my $class = ref $_[0];
    return bless
    {
     value => $uri,
    }, $class;
}


#######################################################################

=head3 authority

=cut

sub authority
{
    return shift->getset('authority',@_);
}


#######################################################################

=head3 path_query

=cut

sub path_query
{
    return shift->getset('path_query',@_);
}


#######################################################################

=head3 path_segments

=cut

sub path_segments
{
    return shift->getset('path_segments',@_);
}


#######################################################################

=head3 query

=cut

sub query
{
    return shift->getset('query',@_);
}


#######################################################################

=head3 query_form

=cut

sub query_form
{
    return shift->getset('query_form',@_);
}


#######################################################################

=head3 query_keywords

=cut

sub query_keywords
{
    return shift->getset('query_keywords',@_);
}


#######################################################################

=head3 userinfo

=cut

sub userinfo
{
    return shift->getset('userinfo',@_);
}


#######################################################################

=head3 host

=cut

sub host
{
    return shift->getset('host',@_);
}


#######################################################################

=head3 port

=cut

sub port
{
    return shift->getset('port',@_);
}


#######################################################################

=head3 host_port

=cut

sub host_port
{
    return shift->getset('host_port',@_);
}


#######################################################################

=head3 default_port

=cut

sub default_port
{
    return $_[0]->{'value'}->default_port;
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
