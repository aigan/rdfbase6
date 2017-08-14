package RDF::Base::Pred::List;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Pred::List

=cut

use 5.014;
use warnings;
use base qw( RDF::Base::List );

use Carp qw(carp croak cluck confess);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump  );

use RDF::Base::Utils qw( is_undef valclean query_desig parse_propargs );


=head1 DESCRIPTION

Inherits from L<RDF::Base::List>

=cut

##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
