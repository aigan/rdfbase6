#  $Id$  -*-cperl-*-
package Rit::Base::Search::Collection;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Search Collection class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Search::Collection

=cut

use strict;
use Carp qw( confess );
use List::Util qw( min );

use constant PAGELIMIT  => 20;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump deunicode throw );

use Rit::Base::Search;
use Rit::Base::Search::Result;


=head1 DESCRIPTION

CGI query parameters reserved for use with some methods are:

  limit

=cut


#######################################################################

=head2 new

=cut

sub new
{
    my( $this ) = @_;
    my $class = ref $this || $this;

    my $search =
    {
     rb_search => [],
     custom_result => undef,
     result => undef,
     is_active => 0,
    };

    bless $search, $class;


    return $search;
}


#######################################################################

=head2 set_result

=cut

sub set_result
{
    my( $search, $result_in ) = @_;

    if( ref $result_in eq 'Rit::Base::List' )
    {
	$search->{'custom_result'} = $result_in;
    }
    else
    {
	confess "Result $result_in not handled";
    }

    return $search->result;
}

#######################################################################

=head2 has_criterions

=cut

sub has_criterions
{
    my( $search ) = @_;

    if( @{$search->{'rb_search'}} or $search->{'custom_result'} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

#######################################################################

=head2 is_rb_search

=cut

sub is_rb_search
{
    if( $_[0]->{'rb_search'}[0] )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

#######################################################################

=head2 result

=cut

sub result
{
    my( $result ) = $_[0]->{'result'};

    unless( $result )
    {
	my( $search ) = @_;

	my %params = ( search => $search );
	$result = $search->{'result'} =
	  $Para::Frame::CFG->{'search_result_class'}->
	    new(undef, \%params );
    }

    unless( $result->{'page_size'} )
    {
	my $limit = 20;
	if( my $req = $Para::Frame::REQ )
	{
	    my $user = $req->user;
	    if( $user and $req->is_from_client )
	    {
		my $q = $req->q;
		$limit = $q->param('limit') || 20;
		$limit = min( $limit, PAGELIMIT ) unless $user->has_root_access;
	    }
	}

	$result->set_page_size( $limit );
    }

    return $result;
}

#######################################################################

=head2 reset

=cut

sub reset
{
    my( $search ) = @_;

    # Removes all rb_search parts
    $search->{'rb_search'} = [];
    $search->{'result'} = undef;
    $search->{'is_active'} = 0;

#    debug "Search collection resetted: ".datadump($search,1);

    return $search;
}

#######################################################################

=head2 reset_result

=cut

sub reset_result
{
    delete $_[0]->{'result'};
}

#######################################################################

=head2 size

=cut

sub size
{
    my( $search ) = @_;

    my $result = $search->result;

    if( $result )
    {
	return $result->size;
    }
    else
    {
	return undef;
    }
}

#######################################################################

=head2 add

 note: only handles rb_search

=cut

sub add
{
    my( $search, $rb_search ) = @_;

    push @{$search->{'rb_search'}}, $rb_search;
    return $search;
}

#######################################################################

=head2 add_first

 note: only handles rb_search

Makes this the first search part

=cut

sub add_first
{
    my( $search, $rb_search ) = @_;

    unshift @{$search->{'rb_search'}}, $rb_search;
    return $search;
}

#######################################################################

=head2 first_rb_part

=cut

sub first_rb_part
{
    my( $search ) = @_;

   return $search->{'rb_search'}[0] ||=
     Rit::Base::Search->new();
}

#######################################################################

=head2 rb_parts

=cut

sub rb_parts
{
    my( $search ) = @_;

#    debug "rb_search: ".datadump($search->{'rb_search'}[0],2);
    return $search->{'rb_search'} ||= [];
}

#######################################################################

=head2 modify

=cut

sub modify
{
    my $parts = shift->rb_parts;
    debug sprintf "MODIFYING %d parts", scalar(@$parts);
    foreach my $s (@$parts)
    {
	debug "  MODIFYING search $s";
	$s->modify(@_);
    }
}

#######################################################################

=head2 add_stats

=cut

sub add_stats
{
    foreach my $s (@{shift->rb_parts})
    {
	$s->add_stats(@_);
    }
}

#######################################################################

=head2 order_default

=cut

sub order_default
{
    foreach my $s (@{shift->rb_parts})
    {
	$s->order_default(@_);
    }
}


#######################################################################

=head2 execute

=cut

sub execute
{
    my( $search ) = shift;
    foreach my $s (@{$search->rb_parts})
    {
	$s->execute(@_);
    }

    $search->{'is_active'} = 1;
}


#######################################################################

=head2 is_active

=cut

sub is_active
{
    return $_[0]->{'is_active'};
}


#######################################################################

=head2 set_active

=cut

sub set_active
{
    return $_[0]->{'is_active'} = 1;
}


#######################################################################

=head2 result_url

=cut

sub result_url
{
    $_[0]->{'result_url'} = $_[1] if defined $_[1];
    return $_[0]->{'result_url'} ||
      $Para::Frame::REQ->site->home->url_path_slash;
}


#######################################################################

=head2 form_url

=cut

sub form_url
{
    $_[0]->{'form_url'} = $_[1] if defined $_[1];
    return $_[0]->{'form_url'} ||
      $Para::Frame::REQ->site->home->url_path_slash;
}


######################################################################

=head2 set_page_size

  $l->set_page_size( $page_size )

Sets and returns the given C<$page_size>

=cut

sub set_page_size
{
    return $_[0]->{'page_size'} = int($_[1]);
}


#######################################################################

1;
