package Rit::Base::Session;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Rit::Base::Session

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Session );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

use Rit::Base::Search::Collection;

=head1 DESCRIPTION

Ritbase Resource Session class

=cut

###########################################################################

=head2 search_collection

=cut

sub search_collection
{
    my( $s, $val ) = @_;
    if( defined $val )
    {
	return $s->{'search_collection'} = $val;
    }

    return $s->{'search_collection'} ||=
      $Para::Frame::CFG->{'search_collection_class'}->new();
}

###########################################################################

1;
