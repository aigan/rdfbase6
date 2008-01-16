#  $Id$  -*-cperl-*-
package Rit::Base::Search::Result;

=head1 NAME

Rit::Guides::Base::Result

=cut

use strict;
use Carp qw( confess );
use Scalar::Util qw(weaken);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump deunicode throw );
use Para::Frame::List;

use Rit::Base::Search::Collection;
use Rit::Base::Utils qw( query_desig );

use base 'Para::Frame::List';

#######################################################################

=head2 init

=cut

sub init
{
    my( $res, $args ) = @_;

    $res->{'search'} = $args->{'search'}
      or confess "Obj init misses search arg ".datadump($res,1);
#    weaken( $res->{'search'} );

    $args->{'materializer'} = \&materialize;

#    debug "Initiating a new search result";
#    debug datadump($res, 3);

    return $res;
}

sub DESTROY
{
#    warn "DESTROYING $_[0]";
    undef $_[0]->{'search'};
}


#######################################################################

sub clone_props
{
    my( $l ) = @_;
    my $args = $l->SUPER::clone_props;
    $args->{'search'} = $l->{'search'};
    return $args;
}


#######################################################################

=head2 materialize

=cut

sub materialize
{
    my( $l, $i ) = @_;

    my $elem = $l->{'_DATA'}[$i];
    if( ref $elem )
    {
	return $elem;
    }
    else
    {
#	my $ts = Time::HiRes::time();
	my $node = Rit::Base::Resource->get( $elem );
	if( debug > 1 )
	{
	    debug "Materializing Search result $i: ".$node->sysdesig;
	}
#	$Para::Frame::REQ->{RBSTAT}{materialize} += Time::HiRes::time() - $ts;
	$Para::Frame::REQ->may_yield;
	return $node;
    }
}

#######################################################################

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

#######################################################################

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
		$uniq->{$elem}++;
	    }
	}

	foreach my $elem (@$arrayref)
	{
	    unless( $uniq->{$elem}++ )
	    {
		push @$data, $elem;
	    }
	}
    }
    else
    {
	push @$data, @$arrayref;
    }
    return 1;
}


#######################################################################

=head2 search

=cut

sub search
{
    return $_[0]->{'search'} ||
      confess "No search object registred ".datadump($_[0],1);
}

#######################################################################

1;
