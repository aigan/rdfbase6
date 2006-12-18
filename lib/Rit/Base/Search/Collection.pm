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
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Guides::Search::Collection

=cut

use strict;
use Carp qw( confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump deunicode throw );

use Rit::Base::Search;
use Rit::Base::Search::Result;

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

=head2 result

=cut

sub result
{
    my( $search ) = @_;

    return $search->{'result'} ||=
      $Para::Frame::CFG->{'search_result_class'}->
	new(undef, {search => $search});
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
    foreach my $s (@{shift->rb_parts})
    {
	$s->execute(@_);
    }
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


#######################################################################

1;
