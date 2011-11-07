package RDF::Base::Search::Result;
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

RDF::Base::Search::Result

=cut

use 5.010;
use strict;
use warnings;
use base 'RDF::Base::List';
use constant PAGE_SIZE_MAX  => 20;
use constant LIMIT_DISPLAY_MAX   => 80;

use Carp qw( confess );
use Scalar::Util qw(weaken);
use List::Util;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump deunicode throw );
use Para::Frame::List;

use RDF::Base::Search::Collection;
use RDF::Base::Utils qw( query_desig );


##############################################################################

=head2 init

Initializes result object from the Collection properties

=cut

sub init
{
    my( $res, $args ) = @_;

    $res->{'search'} = $args->{'search'}
      or confess "Obj init misses search arg ".datadump($res,1);
#    weaken( $res->{'search'} );

    $args->{'materializer'} = \&RDF::Base::List::materialize;

#    debug "Initiating a new search result";
#    debug datadump($res, 3);

    my $search = $res->{'search'};


    ### init type
    #
    # TODO: implemet this

    ### init materializer
    #
    my $materializer = $args->{'materializer'} || $search->{'materializer'};
    unless( $materializer )
    {
	foreach my $part ( $search->parts )
	{
	    my $pmat = $part->{'materializer'};
	    $materializer ||= $pmat;
	    unless( $materializer eq $pmat )
	    {
		my $out = "Materializer mismatch\n";
		foreach my $epart ( $search->parts )
		{
		    $out .= " * $epart->{meterializer}\n";
		}
		confess $out;
	    }
	}
	$res->{'materializer'} = $materializer;
    }



    ### init other properties
    #
    foreach my $prop (qw( allow_undef page_size display_pages limit_pages limit_display ))
    {
	$res->{$prop} ||= $search->{$prop} || 0;
    }

    ### init page_size
    $res->{'page_size'} ||= PAGE_SIZE_MAX;
    $res->{'limit_display'} ||= 100000;

    ### Restrict based on root access
    #
    if( $Para::Frame::U and not $Para::Frame::U->has_root_access )
    {
	$res->{'page_size'} = List::Util::min( $res->{'page_size'}, PAGE_SIZE_MAX );
#	debug "page_size set to ".$res->{'page_size'} ." * ".PAGE_SIZE_MAX;

	$res->{'limit_display'} = List::Util::min( $res->{'limit_display'}, LIMIT_DISPLAY_MAX );
#	debug "limit_display set to ".$res->{'limit_display'}." * ".LIMIT_DISPLAY_MAX;
    }

    return $res;
}

sub DESTROY
{
#    warn "DESTROYING $_[0]";
    undef $_[0]->{'search'};
}


##############################################################################

sub clone_props
{
    # CHECKME: Is this used anywhere?!

    my( $l ) = @_;
    my $args = $l->SUPER::clone_props;
    $args->{'search'} = $l->{'search'};
    return $args;
}


##############################################################################

=head2 populate_all

=cut

sub populate_all
{
    my( $l ) = @_;

#    debug "POPULATING RB result";

    return $l->{'_DATA'} if $l->{'populated'} > 1;

    my $limit = $l->{'limit'};

    my $search = $l->search;
#    debug "Using search obj $search".datadump($search);

    foreach my $rb_search ( @{$search->{'rb_search'}} )
    {
#	debug "Adding data from $rb_search";
	$l->add_part( $rb_search->result->as_raw_arrayref);
    }
    if( my $res = $search->{'custom_result'} )
    {
#	debug "Adding data from custom result";
	$l->add_part( $res );
    }

    if( $limit )
    {
	if( scalar(@{$_[0]->{'_DATA'}}) > $limit )
	{
	    $#{$_[0]->{'_DATA'}} = ($limit-1); # Set size
	}
    }

    $_[0]->on_populate_all;

    return $_[0]->{'_DATA'};
}

##############################################################################

=head2 add_part

=cut

sub add_part
{
    my( $l, $arrayref ) = @_;

    my $data = $l->{'_DATA'} ||= [];
    if( @$data )
    {
	my $uniq = $l->{'_RG_UNIQ'};
	unless( $uniq )
	{
	    $uniq = $l->{'_RG_UNIQ'} = {};
	    foreach my $elem ( @$data )
	    {
		my $key = UNIVERSAL::can($elem,'id') ? $elem->id : $elem;
		$uniq->{$key}++;
#		debug " --- ".$key;
	    }
	}

	foreach my $elem (@$arrayref)
	{
	    my $key = UNIVERSAL::can($elem,'id') ? $elem->id : $elem;
	    unless( $uniq->{$key}++ )
	    {
		push @$data, $elem;
#		debug " --- ".$key;
	    }
	}
    }
    else
    {
	push @$data, @$arrayref;
    }
    return 1;
}


##############################################################################

=head2 search

=cut

sub search
{
    return $_[0]->{'search'} ||
      confess "No search object registred ".datadump($_[0],1);
}

##############################################################################

1;
