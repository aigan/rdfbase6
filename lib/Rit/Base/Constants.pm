#  $Id$  -*-cperl-*-
package Rit::Base::Constants;
#=====================================================================
#
# DESCRIPTION
#   Ritbase constants class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Constants

=head1 SYNOPSIS

  use Rit::Base::Constants qw( $C_business_persona );

  $label = $C_business_persona->loc;

=cut

use strict;
use Carp qw( croak cluck confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

#use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base;
use Rit::Base::Utils qw( is_undef );

our %Label; # The initiated constants
our $AUTOLOAD;
our @Initlist; # Constants to export then the DB is online

#######################################################################

=head2 import

  use Constants qw( $C_class ... )

The use statement calls C<import()>

=cut

sub import
{
    my $class = shift;

    my $callpkg = caller();
    no strict 'refs'; # Symbolic refs

    my $temp = bless{NOT_INITIALIZED=>1};

    my $updating_db = 0;
    if( $ARGV[0] and ($ARGV[0] eq 'upgrade') )
    {
	$updating_db = 1;
    }

    foreach my $const ( @_ )
    {
	$const =~ /^\$C_(\w+)/ or croak "malformed constant: $const";
	debug 2, "Package $callpkg imports $1";

	if( $Rit::dbix and not $updating_db  )
	{
	    my $obj = $class->get($1);
	    *{"$callpkg\::C_$1"} = \ $obj;
	}
	else
	{
	    push @Initlist, ["$callpkg\::C_$1", $1];

	    # Temporary placeholder
	    *{"$callpkg\::C_$1"} = \ $temp;
	}
    }
}


######################################################################

=head2 on_startup

=cut

sub on_startup
{
    my( $class ) = @_;

    debug "Initiating constants";

    no strict 'refs'; # Symbolic refs
    foreach my $export (@Initlist)
    {
	debug 2, " * $export->[1]";
	my $obj = $class->get($export->[1]);
	*{$export->[0]} = \ $obj;
    }
}


#######################################################################

=head2 new

=cut

sub new ()
{
    return bless {};
}


######################################################################

=head2 find

  Rit::Base::Constants->find(\%query, \%args)

Adds the criterion { label_exist => 1 } and calls
L<Rit::Base::Resource/find>

=cut

sub find
{
    my( $this, $query, $args ) = @_;

    unless( UNIVERSAL::isa $query, 'HASH' )
    {
	confess "Query must be a hashref";
    }

    $query->{'label_exist'} = 1;

    return Rit::Base::Resource->find($query, $args);
}



######################################################################

=head2 get_by_id

  Rit::Base::Constants->get_by_id( $id )

Returns:

a L<Rit::Base::Constant> object or L<Rit::Base::Undef>

=cut

sub get_by_id
{
    my( $this, $id ) = @_;
    my $node = Rit::Base::Resource->get_by_id($id) or return undef;
    if( $node->label )
    {
	return $node;
    }
    else
    {
	confess "Node $id not a constant";
    }
}



######################################################################

=head2 get

  Rit::Base::Constants->get( $label )

Returns:

a L<Rit::Base::Resource>

Exceptions:

croaks if constant doesn't exist

=cut

sub get
{
    my( $this, $label ) = @_;
    return Rit::Base::Resource->get_by_label( $label );
}



######################################################################

=head2 AUTOLOAD

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
#    debug "Autoloading constant $AUTOLOAD";
    return  $Label{$AUTOLOAD} || Rit::Base::Constants->get($AUTOLOAD);
}

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>,
L<Rit::Base>

=cut
