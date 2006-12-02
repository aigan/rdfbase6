#  $Id$  -*-cperl-*-
package Rit::Base::Object::Compatible;
#=====================================================================
#
# DESCRIPTION
#   Ritbase object metaclass
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Object::Compatible

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

=head1 DESCRIPTION

For testing the identity of objects.

This is a base class for L<Rit::Base::Object> and
L<Rit::Base::Lazy>.

=cut

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>

=cut
