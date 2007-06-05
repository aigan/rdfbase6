#  $Id$  -*-cperl-*-
package Rit::Base::Arc::Lim;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource Arc Lim class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Arc::Lim

=cut

use strict;

use Carp qw( cluck confess croak carp shortmess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch create_file trim debug datadump
			   package_to_module );

use Rit::Base::Resource;

our %LIM =
  (
   active           =>     1,
   inactive         =>     2,
   direct           =>     4,
   indirect         =>     8,
   explicit         =>    16,
   implicit         =>    32,
   disregarded      =>    64,
   not_disregarded  =>   128,
   submitted        =>   256,
   not_submitted    =>   512,
   new              =>  1024,
   not_new          =>  2048,
   old              =>  4096,
   not_old          =>  8192,
   created_by_me    => 16384,
  );

our %REVLIM = reverse %LIM;

use constant FLAGS_INACTIVE => (2+256+512+1024+2048+4096+8192);
use constant FLAGS_ACTIVE   => (1+512+2048+8192);


#########################################################################

=head2 new

=cut

sub new
{
    my $class = shift;
    return bless [], $class;
}

#########################################################################

=head2 parse

  Rit::Base::Arc::Lim->parse( $arclim )

  Rit::Base::Arc::Lim->parse( [$arclim1, $arclim2, ...] )

Returns:

  $arclim

=cut

sub parse
{
    my( $this, $arclim ) = @_;
    my $class = ref $this || $this;

    $arclim ||= [];

    unless( ref $arclim )
    {
	$arclim = [$arclim];
    }

    foreach(@$arclim)
    {
	if( my $val = $LIM{$_} )
	{
	    die "Flag $_ not recognized" unless $val;
	    $_ = $val;
	}
    }

    return( bless $arclim, $class );
}

#########################################################################

=head2 clone

  $arclim->clone

Returns: a copy

=cut

sub clone
{
    return bless [@{$_[0]}], ref $_[0];
}

#########################################################################

=head2 add_intersect

  $arclim->add_intersect( $limit )

=cut

sub add_intersect
{
    my( $arclim, $limit ) = @_;

    unless( $limit =~ /^\d+$/ )
    {
	$limit= $LIM{$limit};
	die "Flag $_[1] not recognized" unless $limit;
    }

    foreach(@$arclim)
    {
	$_ |= +$limit;
    }

    return $arclim;
}

#######################################################################

=head2 incl_act

  $arclim->incl_act()

Stands for "Does the arclim includes active and/or inactive arcs?"

No arclims menas that only active arcs are included.

Returns:

  ($includes_active, $includes_inactive)

=cut

sub incl_act
{
    my( $arclim ) = @_;

    my $active   = 1;
    my $inactive = 0;
    my $other    = 0;

    confess "Invalid arclim ($arclim)" unless ref $arclim;

    if( @$arclim )
    {
	$active = 0;
	foreach(@$arclim)
	{
	    if( $_ & FLAGS_ACTIVE )
	    {
		$active = 1;
	    }

	    if( $_ & FLAGS_INACTIVE )
	    {
		$inactive = 1;
	    }
	}

	unless( $inactive )
	{
	    $active = 1;
	}
    }

    return( $active, $inactive );
}


#######################################################################

=head2 sql

  $this->sql( $arclim, \%args )

Supported args are

  prefix

Returns: The sql string to insert, NOT beginning with "and ..."

=cut

sub sql
{
    my( $arclim, $args ) = @_;

    $args ||= {};

    $arclim ||= [];

    my $pf = $args->{'prefix'} || "";

    unless( @$arclim )
    {
	return "${pf}active is true";
    }

    my @alt;
    foreach( @$arclim )
    {
	my @crit = ();

	if( $_ & $LIM{'active'} )
	{
	    push @crit, "${pf}active is true";
	}

	if( $_ & $LIM{'direct'} )
	{
	    push @crit, "${pf}indirect is false";
	}

	if( $_ & $LIM{'submitted'} )
	{
	    push @crit, "${pf}submitted is true";
	}

	if(  $_ & $LIM{'new'} )
	{
	    push @crit, "(${pf}active is false and ${pf}submitted is false and ${pf}activated is null )";
	}

	if(  $_ & $LIM{'created_by_me'} )
	{
	    my $uid = $Para::Frame::REQ->user->id;
	    push @crit, "${pf}created_by=$uid";
	}

	if(  $_ & $LIM{'old'} )
	{
	    push @crit, "${pf}deactivated is not null";
	}

	if(  $_ & $LIM{'inactive'} )
	{
	    push @crit, "${pf}active is false";
	}

	if( $_ & $LIM{'indirect'} )
	{
	    push @crit, "${pf}indirect is true";
	}

	if( $_ & $LIM{'not_submitted'} )
	{
	    push @crit, "${pf}submitted is false";
	}

	if( $_ & $LIM{'explicit'} )
	{
	    push @crit, "${pf}implicit is false";
	}

	if( $_ & $LIM{'implicit'} )
	{
	    push @crit, "${pf}implicit is true";
	}

	if( $_ & $LIM{'not_new'} )
	{
	    push @crit, "not (${pf}active is false and ${pf}submitted is false and ${pf}activated is null )";
	}

	if( $_ & $LIM{'not_old'} )
	{
	    push @crit, "${pf}deactivated is null";
	}

	if( $_ & $LIM{'not_disregarded'} )
	{
	    # That's all arcs here
	}

	if( $_ & $LIM{'disregarded'} )
	{
	    confess "Limiting to disregarded arcs makes no sense";
	}

	push @alt, join " and ", @crit;
    }

    if( @alt == 1 )
    {
	return $alt[0];
    }
    elsif( @alt > 1 )
    {
	my $joined = join " or ", map "($_)", @alt;
	return "($joined)";
    }
    else
    {
	return "${pf}active is true";
    }
}


#######################################################################

=head2 size

  $this->size

Returns: The number of alternative limits

=cut

sub size
{
    return scalar @{$_[0]};
}


#######################################################################

=head2 sysdesig

  $this->sysdesig( \%args )

=cut

sub sysdesig
{
    my( $arclim ) = @_;

    debug "Generating arclim sysdesig for ".datadump($arclim);

    my @limpart;
    foreach my $lim (@$arclim)
    {
	my @parts;
	my $num = 1;
	while( $num < 16385 )
	{
	    if( $lim & $num )
	    {
		push @parts, $REVLIM{$num};
	    }
	    $num **=2;
	}

	push @limpart, "(".join(' and ', @parts).")";
    }

    return "Arclim ".join(' or ', @limpart).".";
}


#######################################################################

=head2 names

  $this->names

Returns: a list of al lim names

=cut

sub names
{
    return keys %LIM;
}


#########################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Resource>

=cut
