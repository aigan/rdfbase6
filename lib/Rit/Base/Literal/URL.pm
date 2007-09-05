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

use base qw( Para::Frame::URI Rit::Base::Literal::String );
# Parent overloads some operators!


=head1 DESCRIPTION

Represents an URL (or URI). This is a wrapper for L<URI> that
redirects calls to that class. It's extended as a
L<Rit::Base::Literal::String>.

=cut


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

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
