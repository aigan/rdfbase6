package RDF::Base::Action::rule_add;
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

use 5.014;
use warnings;

use Data::Dumper;

use Para::Frame::Utils qw( throw );

use RDF::Base::Pred;
use RDF::Base::Rule;

=head1 DESCRIPTION

RDFbase Action for adding rules

=cut

sub handler
{
    my( $req ) = @_;

    die "implement me";

    throw('denied', "Nope") unless $req->user->has_root_access;

    my $DEBUG = 0;

    my $q = $req->q;

    my $a_str = $q->param('a') or throw('validation', "Saknar A");
    my $b_str = $q->param('b') or throw('validation', "Saknar B");
    my $c_str = $q->param('c') or throw('validation', "Saknar C");

    my $Pred = 'RDF::Base::Pred';
    my $a = $Pred->get( $a_str ) or throw('validation', "A är inte ett existerande predikat");
    my $b = $Pred->get( $b_str ) or throw('validation', "B är inte ett existerande predikat");
    my $c = $Pred->get( $c_str ) or throw('validation', "C är inte ett existerande predikat");

    my $rule = RDF::Base::Rule->create($a, $b, $c );

    return sprintf "Created rule %s", $rule->sysdesig;
}

1;
