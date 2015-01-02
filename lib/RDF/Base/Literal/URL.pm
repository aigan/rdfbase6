package RDF::Base::Literal::URL;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::URL

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::URI RDF::Base::Literal::String );

use Carp qw( cluck confess longmess );
#use CGI;
use URI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use RDF::Base::Utils qw( );


=head1 DESCRIPTION

Represents an URL (or URI). This is a wrapper for L<URI> that
redirects calls to that class. It's extended as a
L<RDF::Base::Literal::String>.

=cut


##############################################################################

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


##############################################################################

=head3 parse

  $this->parse( $value, $valtype )

special args:

  with_host

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    my $val_mod;
    if ( ref $val eq 'SCALAR' )
    {
        $val_mod = $$val;
    }
    elsif ( UNIVERSAL::isa $val, "RDF::Base::Literal::String" )
    {
        $val_mod = $val->plain;
    }
    else
    {
        confess "Can't parse $val";
    }

    if( not length $val_mod )
    {
        $val_mod = undef;
    }
    elsif( $args->{with_host} )
    {
        # Just expecting a domain. But handle some variations
        $val_mod =~ s{^(https?://)?}{http://};
    }


    # Always return the incoming object. This may MODIFY the object
    #
    if ( UNIVERSAL::isa $val, "RDF::Base::Literal::String" )
    {
        $val->{'value'} = URI->new($val_mod);
        $val->{'valtype'} = $valtype;
        return $val;
    }

    # Implementing class may not take scalarref
    return $class->new( $val_mod, $valtype );
}


##############################################################################

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


##############################################################################

=head3 getset

Used by most get/set wrapper methods

Updated the arc

=cut

sub getset
{
    my( $u, $method ) = (shift, shift);
    if ( my $uri = $u->{'value'} )
    {
        if ( @_ and $u->arc )
        {
            my $res = $uri->$method(@_);
            $u->arc->set_value($u->plain);
            return $res;
        }
        return $uri->$method(@_);
    }

    return "";
}


##############################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return $_[0]->sysdesig;
}


##############################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.

=cut

sub literal
{
    return $_[0]->desig;
}


##############################################################################

=head3 loc

  $lit->loc

Just returns the plain string

=cut

sub loc
{
    return $_[0]->desig;
}


##############################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

=cut

sub plain
{
    return $_[0]->as_string;
}


##############################################################################

=head3 getset_query

Used by query get/set wrapper methods

Updated the arc

=cut

sub getset_query
{
    my( $u, $method ) = (shift, shift);
    if ( my $uri = $u->{'value'} )
    {
        if ( (@_>1) and $u->arc )
        {
            my $res = $uri->$method(@_);
            $u->arc->set_value($u->plain);
            return $res;
        }
        return $uri->$method(@_);
    }

    return "";
}


##############################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return RDF::Base::Literal::Class->get_by_label('url');
}

##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Literal>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
