package RDF::Base::Session;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Session

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Session );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );

use RDF::Base::Search::Collection;

=head1 DESCRIPTION

RDFbase Resource Session class

=cut

###########################################################################

=head2 search_collection

=cut

sub search_collection
{
    my( $s, $val ) = @_;
    if ( defined $val )
    {
        return $s->{'search_collection'} = $val;
    }

    return $s->{'search_collection'} ||=
      RDF::Base->Search_Collection->new();
}

###########################################################################

=head2 search_save

  $s->search_save( $collection, $label );

returns the saved $collection.

=cut

sub search_save
{
    my( $s, $col, $label ) = @_;

    my $saved = $s->{'search_saved'} ||= {};

    unless( $col )
    {
        $col = $s->search_collection();
        unless( $col->size )
        {
            throw('validation', "Empty search result");
        }
    }

    my $old_label = $col->label || '';

    $label ||= $old_label;

    unless( $label )
    {
        my $base = $s->user->username .'-';
        my $number = 1;
        while( $saved->{$base . $number } )
        {
            $number ++;
        }

        $label = $base . $number;
    }

    debug "Old label ".$old_label;
    debug "New label ".$label;

    delete $saved->{$old_label};
    $col->label( $label );
    $saved->{$label} = $col;

#    debug "Saved searches now: ".datadump($saved,2);

    return $col;
}

###########################################################################

=head2 search_load

  $s->search_load();
  $s->search_load( $label );

returns the saved $collection. Sets the current search.

=cut

sub search_load
{
    my( $s, $label ) = @_;

    my $saved = $s->{'search_saved'} ||= {};

    unless( $label )
    {
        my $base = $s->user->username .'-';
        my $number = 1;
        $label = $base . $number;
    }

    my $col = $saved->{$label};

    unless( $col )
    {
        throw('notfound', "Search $label not found");
    }

    return $s->{'search_collection'} = $col;
}

###########################################################################

=head2 search_get

  $s->search_get( $label );

returns the saved $collection.

=cut

sub search_get
{
    my( $s, $label ) = @_;

    my $saved = $s->{'search_saved'} ||= {};

    unless( $label )
    {
        throw('validation',"Label missing");
    }

    return $saved->{$label};
}

###########################################################################

=head2 search_saved_list

  $s->search_saved_list

returns a PF/List of collections

=cut

sub search_saved_list
{
    my( $s ) = @_;

    my $saved = $s->{'search_saved'} ||= {};

#    debug datadump($saved,2);

    return Para::Frame::List->new([ values %$saved ]);
}

###########################################################################

=head2 search_delete

  $s->search_delete
  $s->search_delete( $label )

  Returns false if collection was empty.

  Returns the collection deleted from session.

=cut

sub search_delete
{
    my( $s, $label ) = @_;

    my $col;
    if( $label )
    {
        $col = $s->search_get( $label );
    }
    else
    {
        $col = $s->search_collection();
        $label = $col->label;
    }

    if( $label )
    {
        my $saved = $s->{'search_saved'} ||= {};
        delete $saved->{$label};
    }

    if( $col eq $s->search_collection() )
    {
        $s->{'search_collection'} =
          RDF::Base->Search_Collection->new();
    }

    return 0 unless scalar @{$col->parts};

    return $col;
}

###########################################################################

1;
