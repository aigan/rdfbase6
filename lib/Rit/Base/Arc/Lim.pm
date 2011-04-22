package Rit::Base::Arc::Lim;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Rit::Base::Arc::Lim

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( cluck confess croak carp shortmess );
use List::Util;

use base qw( Exporter );
our @EXPORT_OK = qw( limflag );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch create_file trim debug datadump
			   package_to_module parse_perlstruct );

use Rit::Base::Resource;
use Rit::Base::Utils qw( query_desig );


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
   created_by_me    => 16384, # Not used alone!
   removal          => 32768,
   not_removal      => 65536,

   adirect          =>     5, # active + direct
  );

our %REVLIM = reverse %LIM;

use constant FLAGS_INACTIVE => (2+256+512+1024+2048+4096+8192+32768+65536);
use constant FLAGS_ACTIVE   => (1+512+2048+8192+65536);

#########################################################################

=head2 new

=cut

sub new
{
    my $class = shift;
    return bless [], $class;
}

#########################################################################

=head2 parse_string

  Rit::Base::Arc::Lim->parse( "$arclim" )

  Rit::Base::Arc::Lim->parse( "[$arclim1, $arclim2, ...]" )

  Rit::Base::Arc::Lim->parse( "[ [$arclim1, $arclim2, ...], [...], ... ]" )

Same as L</parse> but takes a string rather than an arrayref

Returns:

  $arclim

=cut

sub parse_string
{
    my( $this, $string_in ) = @_;

    return $this->parse( parse_perlstruct( $string_in ) );
}


#########################################################################

=head2 parse

  Rit::Base::Arc::Lim->parse( $arclim )

  Rit::Base::Arc::Lim->parse( [$arclim1, $arclim2, ...] )

  Rit::Base::Arc::Lim->parse( [ [$arclim1, $arclim2, ...], [...], ... ] )

The second level arrayrefs are ANDed together. First lever are ORed
together. [ [l1, l2], l3, [l4,l5] ] meens that the arc is accepted if
it passes( (l1 and l2) or l3 or (l4 and l5) ).

Returns:

  $arclim

=cut

sub parse
{
    my( $this, $arclim ) = @_;
    my $class = ref $this || $this;

    $arclim ||= [];

#    debug "Parsing arclim ".query_desig($arclim);

    unless( ref $arclim )
    {
	$arclim = [$arclim];
    }

    if( ref $arclim eq 'Rit::Base::Arc::Lim' )
    {
	return $arclim;
    }

    unless( ref $arclim eq 'ARRAY' )
    {
	confess "Invalid arclim: ".query_desig($arclim);
    }

    foreach(@$arclim)
    {
	if( ref $_ and ref $_ eq 'ARRAY' )
	{
	    my $res_lim = 0;
	    foreach my $lim (@$_)
	    {
		next unless $lim;
		unless( $lim =~ /^\d+$/ )
		{
		    die "Flag $lim not recognized" unless $LIM{$lim};
		    $lim = $LIM{$lim};
		}
		$res_lim |= +$lim;
	    }
	    $_ = $res_lim;
	}
	else
	{
	    if( my $val = $LIM{$_} )
	    {
		die "Flag $_ not recognized" unless $val;
		$_ = $val;
	    }
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

  $arclim->add_intersect( $limit, $limit2, ... )

Adds the given limit to each alternative in the arclim. If arclim is
empty the limit is used as the only alternative.

Example:

  $arclim->add_intersect('direct')

For the arclim C<['submitted','active']> this would give C<[['submitted','direct'],['active','direct']]>.

For the arclim C<[]> this would give C<['direct']>.

Returns: The same arclim, changed

=cut

sub add_intersect
{
    my $arclim = shift;

    while( my $limit = shift )
    {
	unless( $limit =~ /^\d+$/ )
	{
	    $limit= $LIM{$limit};
	    die "Flag $_[1] not recognized" unless $limit;
	}

	if( @$arclim )
	{
	    foreach(@$arclim)
	    {
		$_ |= +$limit;
	    }
	}
	else
	{
	    $arclim->[0] = $limit;
	}
    }

#    debug "RETURNING ".$arclim->sysdesig;
    return $arclim;
}

##############################################################################

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

    confess "Invalid arclim ($arclim)" unless ref $arclim;

    if( @$arclim )
    {
	$active = 0;
	foreach(@$arclim)
	{
	    $_||=0;
	    if( $_ & FLAGS_ACTIVE )
	    {
		$active = 1;
	    }

	    if( $_ & FLAGS_INACTIVE )
	    {
		$inactive = 1;
	    }
	}

	unless( $active or $inactive )
	{
	    $active = 1;
	    $inactive = 1;
	}
    }

    return( $active, $inactive );
}


##############################################################################

=head2 sql

  $arclim->sql( \%args )

Supported args are

  prefix


C<$extralim> is the number of limitations other than active and
inactive as the second argument. Used in L<Rit::Base::Resource> in
order to find out the cache status.


Returns in scalar context:  The sql string to insert, NOT beginning with "and ..."

Returns in list context: ( $sql, $extralim )


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

    my $extralim = 0;
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
	    $extralim++;
	}

	if( $_ & $LIM{'submitted'} )
	{
	    push @crit, "${pf}submitted is true";
	    $extralim++;
	}

	if(  $_ & $LIM{'new'} )
	{
	    push @crit, "(${pf}active is false and ${pf}submitted is false and ${pf}deactivated is null )";
	    $extralim++;
	}

	if(  $_ & $LIM{'created_by_me'} and $Para::Frame::REQ )
	{
	    my $uid = $Para::Frame::REQ->user->id;
	    push @crit, "${pf}created_by=$uid";
	    $extralim++;
	}

	if(  $_ & $LIM{'old'} )
	{
	    push @crit, "${pf}deactivated is not null";
	    $extralim++;
	}

	if(  $_ & $LIM{'inactive'} )
	{
	    push @crit, "${pf}active is false";
	}

	if( $_ & $LIM{'indirect'} )
	{
	    push @crit, "${pf}indirect is true";
	    $extralim++;
	}

	if( $_ & $LIM{'not_submitted'} )
	{
	    push @crit, "${pf}submitted is false";
	    $extralim++;
	}

	if( $_ & $LIM{'explicit'} )
	{
	    push @crit, "${pf}implicit is false";
	    $extralim++;
	}

	if( $_ & $LIM{'implicit'} )
	{
	    push @crit, "${pf}implicit is true";
	    $extralim++;
	}

	if( $_ & $LIM{'removal'} )
	{
	    push @crit, "${pf}valtype=0";
	    $extralim++;
	}

	if( $_ & $LIM{'not_removal'} )
	{
	    push @crit, "${pf}valtype<>0";
	    $extralim++;
	}

	if( $_ & $LIM{'not_new'} )
	{
	    push @crit, "not (${pf}active is false and ${pf}submitted is false and ${pf}activated is null )";
	    $extralim++;
	}

	if( $_ & $LIM{'not_old'} )
	{
	    push @crit, "${pf}deactivated is null";
	    $extralim++;
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

    my $sql;
    if( @alt == 1 )
    {
	$sql = $alt[0];
    }
    elsif( @alt > 1 )
    {
	my $joined = join " or ", map "($_)", @alt;
	$sql = "($joined)";
    }
    else
    {
	$sql = "${pf}active is true";
    }

    if( my $aod = $args->{active_on_date} )
    {
	$sql .= " and ${pf}activated <= '$aod' and (${pf}deactivated > '$aod' or ${pf}deactivated is null)";
	$extralim++;
    }


    if( wantarray )
    {
	return( $sql, $extralim );
    }
    else
    {
	return $sql;
    }
}


##############################################################################

=head2 sql_prio

  $this->sql_prio( $arclim, \%args )

Returns: The sql prio for use in L<Rit::Base::Search>

=cut

sub sql_prio
{
    my( $arclim, $args ) = @_;

    $args ||= {};

    $arclim ||= [];

    unless( @$arclim )
    {
	return 9;
    }

    my @alt;

    foreach( @$arclim )
    {
	my $prio = 9;
	if( $_ & $LIM{'submitted'} )
	{
	    $prio = List::Util::min( $prio, 3 );
	}

	if(  $_ & $LIM{'new'} )
	{
	    $prio = List::Util::min( $prio, 4 );
	}

	if(  $_ & $LIM{'created_by_me'} )
	{
	    $prio--;
	}

	if(  $_ & $LIM{'old'} )
	{
	    $prio = List::Util::min( $prio, 5 );
	}

	if( $_ & $LIM{'removal'} )
	{
	    $prio = List::Util::min( $prio, 5 );
	}

	push @alt, $prio;
    }

    return List::Util::max(@alt);
}


##############################################################################

=head2 size

  $this->size

Returns: The number of alternative limits

=cut

sub size
{
    return scalar @{$_[0]};
}


#########################################################################

=head2 sortorder

  $arclim->sortorder( $arc )

Checks which of tha lims in the arclim that the arc matches, in
order. The first is numbered 0. No match gives $number_of_tests + 1.

Returns: A plain number

=cut

sub sortorder
{
    my( $arclim, $arc ) = @_;

    my $i;
    for( $i=0; $i<=$#$arclim; $i++ )
    {
	if( arc_meets_lim( $arc, $arclim->[$i] ) )
	{
	    return $i+1;
	}
    }
    return $i+1;
}

##############################################################################

=head2 sysdesig

  $this->sysdesig( \%args )

=cut

sub sysdesig
{
    my( $arclim ) = @_;

#    debug "Generating arclim sysdesig for ".datadump($arclim);

    my @limpart;
    foreach my $lim (@$arclim)
    {
#	debug "  lim $lim";
	my @parts;
	my $num = 1;
	while( $num < 16385 )
	{
#	    debug "    num $num";
	    if( $lim & $num )
	    {
		push @parts, $REVLIM{$num};
#		debug "      matched";
	    }
	    $num *=2;
	}

	push @limpart, "(".join(' and ', @parts).")";
    }

    return join(' or ', @limpart).".";
}


##############################################################################

=head2 names

  $this->names

Returns: an arrayref of all lim names

=cut

sub names
{
    return [keys %LIM];
}


##############################################################################

=head2 includes

  $arclim->includes( $limname )

Returns: boolean

=cut

sub includes
{
    my( $arclim, $limname ) = @_;

    return 0 unless $LIM{$limname};
    foreach my $lim (@$arclim)
    {
	return 1 if $lim & $LIM{$limname};
    }

    return 0;
}


##############################################################################

=head1 Functions

=head2 limflag

  limflag( $label )

  limflag( $label1, $label2, ... )

Supported lables are:

  active
  inactive

  direct
  indirect

  explicit
  implicit

  disregarded
  not_disregarded

  submitted
  not_submitted

  new
  not_new

  old
  not_old

  removal
  not_removal

  created_by_me

  adirect = active + direct

Returns: the corresponding limit as a number to be used for
arclim. Additional limits are added together.

=cut

sub limflag
{
    my $val = 0;
    while( pop )
    {
	$val += ($LIM{ $_ }||
		 (die "Flag $_ not recognized"));
    }
    return  $val;
}


##############################################################################

=head2 arc_meets_lim

  arc_meets_lim( $arc, $lim )

Returns: boolean

=cut

sub arc_meets_lim
{
    my( $arc, $lim ) = @_;

    if( $lim & $LIM{'active'} )
    {
	return 0 unless $arc->active;
    }

    if( $lim & $LIM{'direct'} )
    {
	return 0 unless $arc->direct;
    }

    if( $lim & $LIM{'submitted'} )
    {
	return 0 unless $arc->submitted;
    }

    if(  $lim & $LIM{'new'} )
    {
	return 0 unless $arc->is_new;
    }

    if(  $lim & $LIM{'created_by_me'} )
    {
	return 0 unless $arc->created_by->equals($Para::Frame::REQ->user);
    }

    if(  $lim & $LIM{'old'} )
    {
	return 0 unless $arc->old;
    }

    if(  $lim & $LIM{'inactive'} )
    {
	return 0 unless $arc->inactive;
    }

    if( $lim & $LIM{'indirect'} )
    {
	return 0 unless $arc->indirect;
    }

    if( $lim & $LIM{'not_submitted'} )
    {
	return 0 if     $arc->submitted;
    }

    if( $lim & $LIM{'explicit'} )
    {
	return 0 unless $arc->explicit;
    }

    if( $lim & $LIM{'implicit'} )
    {
	return 0 unless $arc->implicit;
    }

    if( $lim & $LIM{'removal'} )
    {
	return 0 unless $arc->is_removal;
    }

    if( $lim & $LIM{'not_removal'} )
    {
	return 0 if     $arc->is_removal;
    }

    if( $lim & $LIM{'not_new'} )
    {
	return 0 if     $arc->is_new;
    }

    if( $lim & $LIM{'not_old'} )
    {
	return 0 if     $arc->old;
    }

    if( $lim & $LIM{'not_disregarded'} )
    {
	return 0 unless $arc->not_disregarded;
    }

    if( $lim & $LIM{'disregarded'} )
    {
	return 0 if     $arc->not_disregarded;
    }

    return 1;
}


##############################################################################

=head2 literal_meets_lim

  literal_meets_lim( $arc, $lim )

Returns: boolean

=cut

sub literal_meets_lim
{
    my( $lit, $lim ) = @_;

    if( $lim & $LIM{'active'} )
    {
	# Always active
    }

    if( $lim & $LIM{'direct'} )
    {
	# Always direct
    }

    if( $lim & $LIM{'submitted'} )
    {
	return 0; # Never submitted
    }

    if(  $lim & $LIM{'new'} )
    {
	return 0; # Never new
    }

    if(  $lim & $LIM{'created_by_me'} )
    {
	return 0 unless $lit->created_by->equals($Para::Frame::REQ->user);
    }

    if(  $lim & $LIM{'old'} )
    {
	return 0; # never old
    }

    if(  $lim & $LIM{'inactive'} )
    {
	return 0; # never inactive
    }

    if( $lim & $LIM{'indirect'} )
    {
	return 0; # never indirect
    }

    if( $lim & $LIM{'not_submitted'} )
    {
	# Always not submitted
    }

    if( $lim & $LIM{'explicit'} )
    {
	# Always explicit
    }

    if( $lim & $LIM{'implicit'} )
    {
	return 0; # Never implicit
    }

    if( $lim & $LIM{'removal'} )
    {
	# TODO: May this be a removal literal?
	return 0; # Never removal
    }

    if( $lim & $LIM{'not_removal'} )
    {
	# TODO: May this be a removal literal?
	# Always not removal
    }

    if( $lim & $LIM{'not_new'} )
    {
	# Always not new
    }

    if( $lim & $LIM{'not_old'} )
    {
	# Always not old
    }

    if( $lim & $LIM{'not_disregarded'} )
    {
	# Always not_disregarded
    }

    if( $lim & $LIM{'disregarded'} )
    {
	return 0; # Never disregarded
    }

    return 1;
}


#########################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Resource>

=cut
