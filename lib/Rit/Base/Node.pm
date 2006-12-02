#  $Id$  -*-cperl-*-
package Rit::Base::Node;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Node class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Node

=cut

use Carp qw( cluck confess croak carp );
use Data::Dumper;
use strict;
use vars qw($AUTOLOAD);
use Time::HiRes qw( time );
use LWP::Simple (); # Do not import get

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

### Inherit
#
use base qw( Rit::Base::Object );

=head1 DESCRIPTION

Base class for L<Rit::Base::Resource> and L<Rit::Base::Literal>.

Inherits from L<Rit::Base::Object>.

=cut

#######################################################################

=head1 Object creation

1. Call Class->get($identity)

If you know the correct class, call get for that class. Resource
handles the get(). Get handles node chaching.

2. get() calls Class->new($id), blesses the object to the right class
and then calls $obj->init()

3. new($id) calls $obj->initiate_cache, that handles the Resource
cahce part. Caching specific for a subclass must be handled outside
this, in init()

4. init() will store node in cache if not yet existing

The create() method creates a new object and then creates the object
and calls init()

A get_by_rec($rec) will get the node from the cache or create an
object and call init($rec)


=cut


#######################################################################

=head2 is_node

Returns true.

=cut

sub is_node { 1 };

#######################################################################


1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>,
L<Rit::Base::Time>

=cut
