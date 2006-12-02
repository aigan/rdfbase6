#  $Id$  -*-cperl-*-
package Rit::Base::Resource::Compatible;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource metaclass
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Resource::Compatible

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use base qw( Rit::Base::Object::Compatible );

=head1 DESCRIPTION

For testing the identity of objects.

This is a base class for L<Rit::Base::Resource> and
L<Rit::Base::Lazy>.

=cut


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>

=cut
