package RDF::Base::Search::Collection;
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

RDF::Base::Search::Collection

=cut

use 5.010;
use strict;
use warnings;
use Carp qw( confess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump deunicode throw );

use RDF::Base::Search;
use RDF::Base::Search::Result;


=head1 DESCRIPTION

CGI query parameters reserved for use with some methods are:

  limit

=cut


##############################################################################

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


##############################################################################

=head2 set_result

  $s->set_result( $rb_list )

Sets a custom_result, that will be concatenated to the rb_searches by
L<RDF::Base::Search::Result/populate_all>

Returns: The result object returned by L</result>

=cut

sub set_result
{
    my( $search, $result_in ) = @_;

    if( UNIVERSAL::isa $result_in, 'RDF::Base::List' )
    {
        $search->{'custom_result'} = $result_in;
    }
    elsif( ref $result_in eq 'ARRAY' )
    {
       $search->{'custom_result'} = RDF::Base::List->new($result_in);
    }
    else
    {
        debug "Result in is ".datadump($result_in,1);

        confess sprintf( "Result %s not handled", ref($result_in));
    }

    undef $search->{'result'};

    return $search->result;
}

##############################################################################

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

##############################################################################

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

##############################################################################

=head2 result

  $s->result()

Returns: a search result object, based on the class given in
C<$Para::Frame::CFG-E<gt>{search_result_class}>. Defaults to
L<RDF::Base::Search::Result>. See L<RDF::Base/init>

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

    return $result;
}

##############################################################################

=head2 reset


Query params used:

  limit : sets page_size

=cut

sub reset
{
    my( $search ) = @_;

    foreach my $key ( keys %$search )
    {
	delete $search->{$key};
    }


    # Removes all rb_search parts
    $search->{'rb_search'} = [];
    $search->{'is_active'} = 0;

#    $search->{'result'} = undef;
#    delete $search->{'custom_result'};
#
#    # Properties used by RB::Search::Result
#
#    delete $search->{'allow_undef'};
#    delete $search->{'page_size'};
#    delete $search->{'display_pages'};
#    delete $search->{'limit_pages'};
#    delete $search->{'limit_display'};


    if( my $req = $Para::Frame::REQ )
    {
	my $user = $req->user;
	if( $user and $req->is_from_client )
	{
	    my $q = $req->q;

	    $search->{'page_size'} = $q->param('limit');
	}
    }

    return $search;
}

##############################################################################

=head2 reset_result

=cut

sub reset_result
{
    delete $_[0]->{'result'};
    delete $_[0]->{'custom_result'};
}

##############################################################################

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

##############################################################################

=head2 add

 note: only handles rb_search

=cut

sub add
{
    my( $search, $rb_search ) = @_;

    push @{$search->{'rb_search'}}, $rb_search;
    undef $search->{'result'};
    return $search;
}

##############################################################################

=head2 add_first

 note: only handles rb_search

Makes this the first search part

=cut

sub add_first
{
    my( $search, $rb_search ) = @_;

    unshift @{$search->{'rb_search'}}, $rb_search;
    undef $search->{'result'};
    return $search;
}

##############################################################################

=head2 first_rb_part

=cut

sub first_rb_part
{
    my( $search ) = @_;

   return $search->{'rb_search'}[0] ||=
     RDF::Base::Search->new();
}

##############################################################################

=head2 rb_parts

=cut

sub rb_parts
{
    my( $search ) = @_;

#    debug "rb_search: ".datadump($search->{'rb_search'}[0],2);
    return $search->{'rb_search'} ||= [];
}

##############################################################################

=head2 custom_parts

=cut

sub custom_parts
{
    if( $_[0]->{'custom_result'} )
    {
	return [$_[0]->{'custom_result'}];
    }
    else
    {
	return [];
    }
}

##############################################################################

=head2 parts

=cut

sub parts
{
    return [ @{$_[0]->rb_parts}, @{$_[0]->custom_parts} ];
}

##############################################################################

=head2 modify

=cut

sub modify
{
    my( $search ) = shift @_;

    my $parts = $search->rb_parts;
    debug sprintf "MODIFYING %d parts", scalar(@$parts);
    foreach my $s (@$parts)
    {
	debug "  MODIFYING search $s";
	$s->modify(@_);
    }

    undef $search->{'result'};

    return 1;
}

##############################################################################

=head2 add_stats

=cut

sub add_stats
{
    foreach my $s (@{shift->rb_parts})
    {
	$s->add_stats(@_);
    }
}

##############################################################################

=head2 order_default

=cut

sub order_default
{
    foreach my $s (@{shift->rb_parts})
    {
	$s->order_default(@_);
    }
}


##############################################################################

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
    undef $search->{'result'};
}


##############################################################################

=head2 is_active

=cut

sub is_active
{
    return $_[0]->{'is_active'};
}


##############################################################################

=head2 set_active

=cut

sub set_active
{
    return $_[0]->{'is_active'} = 1;
}


##############################################################################

=head2 result_url

=cut

sub result_url
{
    $_[0]->{'result_url'} = $_[1] if defined $_[1];
    return $_[0]->{'result_url'} || '';
}


##############################################################################

=head2 form_url

=cut

sub form_url
{
    $_[0]->{'form_url'} = $_[1] if defined $_[1];
    return $_[0]->{'form_url'} || '';
}


######################################################################

=head2 set_page_size

  $l->set_page_size( $page_size )

This will be the default page size for the result. The result object
can be set to a diffrent size.

Sets and returns the given C<$page_size>

=cut

sub set_page_size
{
    return $_[0]->{'page_size'} = int($_[1]);
}


##############################################################################

1;
