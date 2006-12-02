#  $Id$  -*-cperl-*-
package Rit::Base::User::Meta;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource User metaclass
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::User::Meta

=cut

use Rit::Base::User;
use Rit::Base::Resource;

use base qw( Rit::Base::User Rit::Base::Resource );

=head1 DESCRIPTION

Inherits from L<Rit::Base::User> and L<Rit::Base::Resource>.

=cut

#######################################################################

1;
