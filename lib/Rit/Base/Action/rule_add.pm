#  $Id$  -*-cperl-*-
package Rit::Guides::Action::rule_add;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Rit::Base::Pred;
use Rit::Base::Rule;

sub handler
{
    my( $req ) = @_;

    throw('denied', "Nope") unless $req->user->level >= 20;

    my $changed = 0;
    my $DEBUG = 0;

    my $q = $req->q;

    my $a_str = $q->param('a') or throw('validation', "Saknar A");
    my $b_str = $q->param('b') or throw('validation', "Saknar B");
    my $c_str = $q->param('c') or throw('validation', "Saknar C");

    my $Pred = 'Rit::Base::Pred';
    my $a = $Pred->get( $a_str ) or throw('validation', "A är inte ett existerande predikat");
    my $b = $Pred->get( $b_str ) or throw('validation', "B är inte ett existerande predikat");
    my $c = $Pred->get( $c_str ) or throw('validation', "C är inte ett existerande predikat");

    my $rule = Rit::Base::Rule->add($a, $b, $c );

    return sprintf "Created rule %s", $rule->sysdesig;
}

1;
