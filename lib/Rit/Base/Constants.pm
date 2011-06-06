package Rit::Base::Constants;
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

Rit::Base::Constants

=head1 SYNOPSIS

  use Rit::Base::Constants qw( $C_business_persona );

  $label = $C_business_persona->loc;

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( croak cluck confess );

#use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump catch );

use Rit::Base;
use Rit::Base::Utils qw( is_undef );

our %Label; # The initiated constants
our $AUTOLOAD;
our @Initlist; # Constants to export then the DB is online

##############################################################################

=head2 import

  use Constants qw( $C_class ... )

The use statement calls C<import()>

=cut

sub import
{
    my $class = shift;

    my $callpkg = caller();
    no strict 'refs'; # Symbolic refs

#    my $temp = bless{NOT_INITIALIZED=>1};

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
            my $temp = bless{label=>$1,NOT_INITIALIZED=>1};
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

    eval
    {
	no strict 'refs'; # Symbolic refs
	foreach my $export (@Initlist)
	{
	    debug 2, " * $export->[1]";
	    my $obj = $class->get($export->[1],{nonfatal=>1}) or next;
	    *{$export->[0]} = \ $obj;
	}
    };
    if( $@ )
    {
	debug $@;
	debug "Continuing without constants";
    }

    debug "Initiating key nodes";
    $class->get('class')->initiate_rel;
}


##############################################################################

=head2 new

=cut

sub new ()
{
    return bless {};
}


######################################################################

=head2 hurry_init

=cut

sub hurry_init
{
    debug "Emergancy instantiation of constant ".$_[0]->{label};
    return $_[0]->get($_[0]->{label},{nonfatal=>1});
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

=head2 get_set

  Rit::Base::Constants->get_set( $label )

As get(), but creates the node if not existing.

=cut

sub get_set
{
    my( $this, $label ) = @_;

    my $node;
    eval
    {
	$node = $this->get( $label );
    };
    if( my $err = catch(['notfound']) )
    {
	$node = Rit::Base::Resource->create({label=>$label});
    }

    return $node;
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
    shift;
    return Rit::Base::Resource->get_by_label( @_ );
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

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>,
L<Rit::Base>

=cut
