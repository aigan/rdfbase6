package RDF::Base::Class;
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

RDF::Base::Class

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( cluck confess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use RDF::Base::Utils qw( is_undef parse_propargs );
#use RDF::Base::Constants qw( $C_syllogism $C_is );


=head1 DESCRIPTION

=cut


sub on_configure
{
    my( $class ) = @_;

    debug "----------> RDF::Base::Class on_configure";
}


1;

=head1 SEE ALSO

L<RDF::Base>,

=cut
