package RDF::Base::Domain;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Domain

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Resource );
use constant R => 'RDF::Base::Resource';

use Carp qw( cluck confess carp croak );

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

#use RDF::Base::Utils qw( valclean is_undef parse_propargs );
#use RDF::Base::Constants qw( $C_predicate );


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,

=cut
