package RDF::Base::Class;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Class

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( cluck confess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump
                           package_to_module module_to_package compile );

use RDF::Base::Utils qw( is_undef parse_propargs );

our @INIT_CLASS;
our %MOD_NODE;
our %METHOD_PKG;
our $IN_CLASS_INIT = 0;

=head1 DESCRIPTION

=cut

##############################################################################


sub on_startup
{
    my( $class ) = @_;

#    debug "----------> RDF::Base::Class on_startup";

    Para::Frame->add_hook( 'on_reload', \&class_something_reloaded );

    while( my $cn = shift @INIT_CLASS )
    {
        $cn->class_init();
    }
}


##############################################################################

sub on_first_bless
{
    my( $cn ) = @_;

    if( $Para::Frame::IN_STARTUP )
    {
        push @INIT_CLASS, $cn;
        return;
    }

    $cn->class_init();
}

##############################################################################

sub class_init
{
    my( $cn ) = @_;

    foreach my $chbpm ( $cn->list('class_handled_by_perl_module')->as_array )
    {
        my $pkg = $chbpm->code->plain;
        my $mod = package_to_module($pkg);

        $MOD_NODE{ $mod }{ $cn->id } = $cn;

        unless( $INC{$mod} )
        {
            $IN_CLASS_INIT = 1;
            eval
            {
                compile($mod);
            };
            $IN_CLASS_INIT = 0;
            die $@ if $@;
        }

        no strict 'refs';           # Symbolic refs
        my @cm = @{$pkg."::CLASS_METHODS"};

        foreach my $m ( @cm )
        {
            $cn->class_register_method( $pkg, $m );
        }
    }
}

##############################################################################

sub class_register_method
{
    my( $cn, $pkg, $method ) = @_;

#    debug sprintf "****** Class %s registers method %s in %s", $cn->desig, $method, $pkg;

    die "malformed method name $method" unless $method =~ /^[_a-z]+$/;

    eval sprintf 'sub %s {class_method("%s", @_)}', $method, $method;

    $METHOD_PKG{ $method }{ $pkg } = 1;
}

##############################################################################

sub class_method
{
    my( $method ) = shift;

    my $list_class;
    my @list;
    no strict 'refs';           # Symbolic refs
    foreach my $pkg ( keys %{$METHOD_PKG{ $method }} )
    {
        my $res = &{"${pkg}::${method}"}(@_);
        if ( UNIVERSAL::isa( $res, 'RDF::Base::Object' ) )
        {
            if ( $res->is_list )
            {
                $list_class ||= ref($res);
                if ( $res->size )
                {
                    CORE::push @list, $res->as_array;
                }
            }
            elsif ( $res->defined )
            {
                $list_class ||= $res->list_class;
                CORE::push @list, $res;
            }
        }
        else
        {
            CORE::push @list, $res;
        }
    }

    if ( my $size = scalar @list )
    {
        if ( $size == 1 )
        {
            return $list[0];
        }
        else
        {
            $list_class ||= "RDF::Base::List";
            return $list_class->new(\@list);
        }
    }
    else
    {
        return is_undef;
    }
}

##############################################################################

sub class_something_reloaded
{
    return if $IN_CLASS_INIT;
    my( $mod ) = @_;

    return unless $MOD_NODE{ $mod };

    foreach my $cn ( values %{$MOD_NODE{$mod}} )
    {
        $cn->class_init();
    }
}

##############################################################################


1;

=head1 SEE ALSO

L<RDF::Base>,

=cut
