package RDF::Base::Action::translation_update;
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

use Para::Frame::L10N qw( loc );
use Para::Frame::Utils qw( throw );

=head1 DESCRIPTION

RDFbase Action for updating a translation

=cut

sub handler
{
    my ($req) = @_;

    my $dbh = $RDF::dbix->dbh;
    my $q = $req->q;

    my $orig = $q->param('orig');
    my $delete = $q->param('remove');

    my $c = $q->param('c') || '';
    my $sv = $q->param('sv');
    my $en = $q->param('en');
    my $de = $q->param('de');
    my $no = $q->param('no');
    my $dk = $q->param('dk');
    my $fi = $q->param('fi');
    my $is = $q->param('is');

    throw('incomplete', 'Ange c') unless length $c;

    if( $delete )
    {
	my $remove_sth = $dbh->prepare("DELETE FROM tr where c=?");
	$remove_sth->execute($orig);
    }
    elsif( $orig )
    {
	my $update_sth = $dbh->prepare("UPDATE tr SET c=?, sv=?, en=?, de=?, no=?, dk=?, fi=?, \"is\"=? WHERE c=?");
	$update_sth->execute($c, $sv, $en, $de, $no, $dk, $fi, $is, $orig);
    }
    else
    {
	my $create_sth = $dbh->prepare("INSERT INTO tr (c, sv, en, de, no, dk, fi, \"is\") VALUES (?,?,?,?,?,?,?,?)");
	$create_sth->execute($c, $sv, $en, $de, $no, $dk, $fi, $is);
    }

    # Reset cache
    delete $RDF::Base::L10N::TRANSLATION{ $c };

    return loc("Translation updated");
}

1;
