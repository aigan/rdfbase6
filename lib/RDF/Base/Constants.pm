package RDF::Base::Constants;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Constants

=head1 SYNOPSIS

  use RDF::Base::Constants qw( $C_business_persona );

  $label = $C_business_persona->loc;

=cut

use 5.014;
use warnings;

use Carp qw( croak cluck confess );

#use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump catch );

use RDF::Base;
use RDF::Base::Utils qw( is_undef );

our %Label;                     # The initiated constants
our $AUTOLOAD;
our @Initlist;             # Constants to export when the DB is online
our $On_startup;

##############################################################################

=head2 import

  use Constants qw( $C_class ... )

The use statement calls C<import()>

=cut

sub import
{
    my $class = shift;

    my $callpkg = caller();
    no strict 'refs';           # Symbolic refs

#    my $temp = bless{NOT_INITIALIZED=>1};

    my $updating_db = 0;
    if ( $ARGV[0] and ($ARGV[0] eq 'upgrade') )
    {
        $updating_db = 1;
    }

    foreach my $const ( @_ )
    {
        $const =~ /^\$C_(\w+)/ or croak "malformed constant: $const";
        debug 2, "Package $callpkg imports $1";

        if ( $RDF::dbix and not $updating_db and not $On_startup  )
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

#        cluck "--> ".${"$callpkg\::"}{"C_$1"};
    }
}


######################################################################

=head2 on_startup

=cut

sub on_startup
{
    my( $class ) = @_;

    debug "Initiating key nodes";
    $class->get('class')->initiate_rel;


    debug "Initiating constants";

    $On_startup = 1;

    eval
    {
        no strict 'refs';       # Symbolic refs
        while( my $export = shift @Initlist )
        {
            debug 2, " * $export->[1]";
            my $obj = $class->get($export->[1],{nonfatal=>1}) or next;
            *{$export->[0]} = \ $obj;
        }

#        while( my $node = shift @RDF::Base::Resource::STARTUP_NODES )
#        {
#            debug "prosponed init of ".$node->{id};
#            $node->first_bless->init;
#        }
    };
    if ( $@ )
    {
        debug $@;
        debug "Continuing without constants";
    }

    $On_startup = 0;

#    debug "Initiating key nodes";
#    $class->get('class')->initiate_rel;
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

  RDF::Base::Constants->find(\%query, \%args)

Adds the criterion { label_exist => 1 } and calls
L<RDF::Base::Resource/find>

=cut

sub find
{
    my( $this, $query, $args ) = @_;

    unless( UNIVERSAL::isa $query, 'HASH' )
    {
        confess "Query must be a hashref";
    }

    $query->{'label_exist'} = 1;

    return RDF::Base::Resource->find($query, $args);
}



######################################################################

=head2 get_set

  RDF::Base::Constants->get_set( $label )

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
    if ( my $err = catch(['notfound']) )
    {
        $node = RDF::Base::Resource->create({label=>$label});
    }

    return $node;
}



######################################################################

=head2 get_by_id

  RDF::Base::Constants->get_by_id( $id )

Returns:

a L<RDF::Base::Constant> object or L<RDF::Base::Undef>

=cut

sub get_by_id
{
    my( $this, $id ) = @_;
    my $node = RDF::Base::Resource->get_by_id($id) or return undef;
    if ( $node->label )
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

  RDF::Base::Constants->get( $label )

Returns:

a L<RDF::Base::Resource>

Exceptions:

croaks if constant doesn't exist

=cut

sub get
{
    shift;
    return RDF::Base::Resource->get_by_label( @_ );
}



######################################################################

=head2 AUTOLOAD

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
#    debug "Autoloading constant $AUTOLOAD";
    return  $Label{$AUTOLOAD} || RDF::Base::Constants->get($AUTOLOAD);
}

##############################################################################

=head1 SEE ALSO

  L<Para::Frame>,
  L<RDF::Base>

=cut

  ;
1;
