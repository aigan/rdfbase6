package RDF::Base::Literal::URL::Website;
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

RDF::Base::Literal::URL::Website

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Literal::URL );

use Carp qw( cluck confess longmess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::L10N qw( loc );

use RDF::Base::Utils qw( );


=head1 DESCRIPTION

Extends L<RDF::Base::Literal::URI>

=cut


##############################################################################

=head3 parse

  $class->parse( \$value, \%args )

For parsing any type of input. Expecially as given by html forms.

Supported args are:
  valtype
  coltype
  arclim

Will use L<RDF::Base::Resource/get_by_anything> for lists and queries.

The valtype may be given for cases there the class handles several
valtypes.

Longest TLD name: museum
Also match ip-addresses

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;

    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);
    my $url;

    if ( ref $val eq 'SCALAR' )
    {
        $url = $class->new( $$val_in, $valtype );
    }
    elsif ( UNIVERSAL::isa $val, "RDF::Base::Literal::URL::Website" )
    {
        $url = $val_in;
    }
    elsif ( UNIVERSAL::isa $val, "RDF::Base::Literal::String" )
    {
        $url = $class->new( $val_in->plain, $valtype );
    }
    else
    {
        confess "Can't parse $val";
    }

    return $url unless length( $url->plain ); # undef

    if ( my $scheme = $url->scheme )
    {
        unless( $scheme =~ /^https?$/ )
        {
            my $str = $url->as_string;
            if ( $str =~ s/^([a-z0-9][a-z0-9\-\.]*\.[a-z0-9]{1,6}):(\d+)//i )
            {
                my $host = $1;
                my $port = $2;

                $url->scheme('http');
                $url->host( $host );
                $url->port( $port );
                $url->path_query( $str );
            }
            else
            {
                throw 'validation', loc "Invalid scheme in website URL $url";
            }
        }
    }
    else
    {
        $url->scheme('http');
    }

    unless( $url->host )
    {
        my $path = $url->path || '';
        debug 3, "Initial path is $path";
        if ( $path =~ s/^([a-z0-9][a-z0-9\-\.]*\.[a-z0-9]{1,6}\b)//i )
        {
            my $host = $1;
            $url->host($host);
            $url->path($path);
            debug 3, "Host is now $host";
        }
    }

    if ( my $path = $url->path )
    {
        debug 3, "Path is now $path";
        unless( $path =~ /^\// )
        {
            throw 'validation', loc "Malformed path in website URL $url";
        }
    }
    else
    {
        $url->path('/');
    }

    if ( my $host = $url->host )
    {
        debug 3, "Host is now $host";
        unless ( $host =~ /^[a-z0-9][a-z0-9\-\.]*\.[a-z0-9]{1,6}$/i )
        {
            throw 'validation', loc "Malformed hostname in website URL $url";
        }
    }
    else
    {
        throw 'validation', loc "Hostname missing from website URL $url";
    }

    return $class->new( $url->canonical, $valtype );
}


##############################################################################

=head3 default_valtype

  =cut

  sub default_valtype
{
    return RDF::Base::Literal::Class->get_by_label('website_url');
}

##############################################################################

1;

=head1 SEE ALSO

  L<RDF::Base::Literal::URL>,
  L<Para::Frame::URI>,

  =cut
