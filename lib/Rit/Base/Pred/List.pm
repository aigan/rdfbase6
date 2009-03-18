package Rit::Base::Pred::List;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Pred::List

=cut

use 5.010;
use strict;
use warnings;
use base qw( Rit::Base::List );

use Carp qw(carp croak cluck confess);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump  );

use Rit::Base::Utils qw( is_undef valclean query_desig parse_propargs );


=head1 DESCRIPTION

Inherits from L<Rit::Base::List>

=cut

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
