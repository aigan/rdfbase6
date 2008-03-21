#  $Id$  -*-cperl-*-
package Rit::Base::Session;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Session

=cut

use strict;

use base qw( Para::Frame::Session );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

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
