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

    $dbh->do("CREATE TABLE reltype (
    id integer NOT NULL,
    label text NOT NULL,
    valtype character varying(10)
    )");

    $dbh->do("CREATE TABLE rel (
    id integer DEFAULT nextval('node_seq'::text) NOT NULL,
    subj integer NOT NULL,
    pred integer NOT NULL,
    obj integer,
    valdate timestamp with time zone,
    valtext text,
    valclean text,
    valint integer,
    valfloat double precision,
    updated timestamp with time zone DEFAULT now(),
    updated_by integer NOT NULL,
    indirect boolean DEFAULT false,
    implicit boolean DEFAULT false
    )");

    $dbh->do("CREATE TABLE constant (
    subj integer NOT NULL,
    label character varying(64) NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    updated_by integer NOT NULL
    )");

    $dbh->do("CREATE INDEX rel_subj_idx ON rel USING btree (subj)");

    $dbh->do("CREATE INDEX rel_obj_idx ON rel USING btree (obj)");

    $dbh->do("CREATE INDEX rel_pred_obj_idx ON rel USING btree (pred, obj)");

    $dbh->do("CREATE INDEX rel_pred_clean_idx ON rel USING btree (pred, valclean)");

    $dbh->do("CREATE INDEX rel_pred_int_idx ON rel USING btree (pred, valint)");
    $dbh->do("CREATE INDEX rel_subj_pred_idx ON rel USING btree (subj, pred)");

    $dbh->do("CREATE INDEX rel_pred_idx ON rel USING btree (pred)");


    $dbh->do("CREATE UNIQUE INDEX constant_label_idx ON constant USING btree (label)");

    $dbh->do("ALTER TABLE ONLY rel ADD CONSTRAINT rel_pkey PRIMARY KEY (id)");

    $dbh->do("ALTER TABLE ONLY constant ADD CONSTRAINT constant_pkey PRIMARY KEY (subj)");


}


1;
