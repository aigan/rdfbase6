#  $Id$  -*-cperl-*-
package Rit::Base::Action::setup_db;

use strict;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( parse_arc_add_box );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $dbix = $Rit::dbix;
    my $dbh = $dbix->dbh;

    my $dbuser = $q->param('dbuser') or die "dbuser missing";


    $dbh->do("CREATE SEQUENCE node_seq");

    $dbh->do("CREATE TABLE pred (
    id int NOT NULL UNIQUE,
    label varchar(32) PRIMARY KEY,
    coltype smallint NOT NULL CONSTRAINT coltype_max CHECK (coltype<5)
    )");


    $dbh->do("CREATE TABLE arc (
    id int NOT NULL,
    ver int PRIMARY KEY,
    replaces int REFERENCES arc (ver),
    subj int NOT NULL,
    pred int NOT NULL REFERENCES pred (id),
    source int NOT NULL,
    active boolean NOT NULL,
    indirect boolean NOT NULL,
    implicit boolean NOT NULL,
    submitted boolean NOT NULL,
    read_access int NOT NULL,
    write_access int NOT NULL,
    created TIMESTAMP WITH TIME ZONE NOT NULL,
    created_by int NOT NULL,
    updated TIMESTAMP WITH TIME ZONE NOT NULL,
    activated TIMESTAMP WITH TIME ZONE,
    activated_by int,
    deactivated TIMESTAMP WITH TIME ZONE,
    unsubmitted TIMESTAMP WITH TIME ZONE,
    valtype int NOT NULL,
    obj int CONSTRAINT obj_alone CHECK(valfloat is null and valdate is null and valbin is null and valtext is null),
    valfloat DOUBLE PRECISION CONSTRAINT valfloat_alone CHECK(obj is null and valdate is null and valbin is null and valtext is null),
    valdate TIMESTAMP WITH TIME ZONE CONSTRAINT valdate_alone CHECK(obj is null and valfloat is null and valbin is null and valtext is null),
    valbin BYTEA CONSTRAINT valbin_alone CHECK(obj is null and valfloat is null and valdate is null and valtext is null),
    valtext text CONSTRAINT valtext_alone CHECK(obj is null and valfloat is null and valdate is null and valbin is null) CONSTRAINT valtext_has_valclean CHECK(valclean is not null),
    valclean text CONSTRAINT valclean_has_valtext CHECK(valtext is not null)
    )");

    $dbh->do("CREATE INDEX arc_id_idx ON arc (id)");

    $dbh->do("CREATE INDEX arc_subj_idx ON arc (subj, active)");

    $dbh->do("CREATE INDEX arc_source_idx ON arc (source)");

    $dbh->do("CREATE INDEX arc_submitted_idx ON arc (submitted)");

    $dbh->do("CREATE INDEX arc_createdby_idx ON arc (created_by)");

    $dbh->do("CREATE INDEX arc_activated_idx ON arc (activated)");

    $dbh->do("CREATE INDEX arc_deactivated_idx ON arc (deactivated)");

    $dbh->do("CREATE INDEX arc_activatedby_idx ON arc (activated_by)");

    $dbh->do("CREATE INDEX arc_obj_idx ON arc (obj, active)");

    $dbh->do("CREATE INDEX arc_valfloat_idx ON arc (valfloat, active)");

    $dbh->do("CREATE INDEX arc_valdate_idx ON arc (valdate, active)");

    $dbh->do("CREATE INDEX arc_valtext_idx ON arc (valtext, active)");

    $dbh->do("CREATE INDEX arc_valclean_idx ON arc (valclean, active)");


    $dbh->do("CREATE TABLE constant (
    subj integer NOT NULL UNIQUE,
    label varchar(64) PRIMARY KEY,
    updated timestamp with time zone NOT NULL,
    updated_by integer NOT NULL
    )");

}


1;
