#  $Id$  -*-cperl-*-
package Rit::Base::Literal::URL::Website;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal Website URL class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::URL::Website

=cut

use strict;
use Carp qw( cluck confess longmess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::L10N qw( loc );

use Rit::Base::Utils qw( is_undef );

use base qw( Rit::Base::Literal::URL );
# Parents overloads some operators!


=head1 DESCRIPTION

Extends L<Rit::Base::Literal::URI>

=cut


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

#    my $valclass_in = ref $val_in;
#    debug "Input value is $val_in ($valclass_in)";
#    debug datadump($val_in, 3);

    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);
    my $url;

#    my $valclass = ref $val;
#    debug "preparsed value is $val ($valclass)";
#    debug datadump($val, 3);


    if( ref $val eq 'SCALAR' )
    {
#	debug "val SCALAR: ".datadump($val_in, 3);

	$url = $class->new( $$val_in );
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::URL::Website" )
    {
#	debug "val URL: ".datadump($val_in, 3);

	$url = $val_in;
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
    {
#	debug "val String: ".datadump($val_in, 3);

	my $plain = $val_in->plain;

#	debug "  -> $plain";

	$url = $class->new( $val_in->plain );
    }
    else
    {
	confess "Can't parse $val";
    }

    return $url unless length( $url->plain ); # undef

    if( my $scheme = $url->scheme )
    {
	unless( $scheme =~ /^https?$/ )
	{
	    my $str = $url->as_string;
	    if( $str =~ s/^([a-z\-\.]+\.[a-z]{2,5}):(\d+)//i )
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
	debug "Initial path is $path";
	if( $path =~ s/^([a-z\-\.]+\.[a-z]{2,5}\b)//i )
	{
	    my $host = $1;
	    $url->host($host);
	    $url->path($path);
	    debug "Host is now $host";
	}
    }

    if( my $path = $url->path )
    {
	debug "PAth is now $path";
	unless( $path =~ /^\// )
	{
	    throw 'validation', loc "Malformed path in website URL $url";
	}
    }
    else
    {
	$url->path('/');
    }

    if( my $host = $url->host )
    {
	debug "Host is now $host";
	unless( $host =~ /^[a-z\-\.]+\.[a-z]{2,5}$/ )
	{
	    throw 'validation', loc "Malformed hostname in website URL $url";
	}
    }
    else
    {
	throw 'validation', loc "Hostname missing from website URL $url";
    }

    return $url->canonical;
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Literal::URL>,
L<Para::Frame::URI>,

=cut
