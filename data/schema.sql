CREATE TABLE arc (
    id integer NOT NULL,
    ver integer NOT NULL,
    replaces integer,
    subj integer NOT NULL,
    pred integer NOT NULL,
    source integer NOT NULL,
    active boolean NOT NULL,
    indirect boolean NOT NULL,
    "implicit" boolean NOT NULL,
    submitted boolean NOT NULL,
    read_access integer NOT NULL,
    write_access integer NOT NULL,
    created timestamp with time zone NOT NULL,
    created_by integer NOT NULL,
    updated timestamp with time zone NOT NULL,
    activated timestamp with time zone,
    activated_by integer,
    deactivated timestamp with time zone,
    unsubmitted timestamp with time zone,
    valtype integer NOT NULL,
    weight integer,
    obj integer,
    valfloat double precision,
    valdate timestamp with time zone,
    valbin bytea,
    valtext text,
    valclean text
);

CREATE TABLE node (
    node integer NOT NULL,
    label character varying(64),
    owned_by integer,
    read_access integer,
    write_access integer,
    pred_coltype smallint,
    created timestamp with time zone NOT NULL,
    created_by integer NOT NULL,
    updated timestamp with time zone NOT NULL,
    updated_by integer NOT NULL,
    CONSTRAINT coltype_max CHECK ((pred_coltype < 10))
);

CREATE SEQUENCE node_seq
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE INDEX arc_activated_idx ON arc USING btree (activated);
CREATE INDEX arc_activatedby_idx ON arc USING btree (activated_by);
CREATE INDEX arc_createdby_idx ON arc USING btree (created_by);
CREATE INDEX arc_deactivated_idx ON arc USING btree (deactivated);
CREATE INDEX arc_id_idx ON arc USING btree (id);
CREATE INDEX arc_obj_idx ON arc USING btree (obj, active);
CREATE INDEX arc_pred_idx ON arc USING btree (pred);
CREATE INDEX arc_source_idx ON arc USING btree (source);
CREATE INDEX arc_subj_idx ON arc USING btree (subj, active);
CREATE INDEX arc_subj_pred_idx ON arc ( subj, pred, active );
CREATE INDEX arc_submitted_idx ON arc USING btree (submitted);
CREATE INDEX arc_valclean_idx ON arc USING btree (valclean, active);
CREATE INDEX arc_valdate_idx ON arc USING btree (valdate, active);
CREATE INDEX arc_valfloat_idx ON arc USING btree (valfloat, active);
CREATE INDEX arc_valtext_idx ON arc USING btree (valtext, active);
CREATE INDEX arc_replaces_idx ON arc USING btree (replaces);

CREATE INDEX node_created_by_idx ON node USING btree (created_by);
CREATE INDEX node_created_idx ON node USING btree (created);
CREATE INDEX node_label_idx ON node USING btree (label);
CREATE INDEX node_ownded_by_idx ON node USING btree (owned_by);
CREATE INDEX node_updated_by_idx ON node USING btree (updated_by);
CREATE INDEX node_updated_idx ON node USING btree (updated);

ALTER TABLE ONLY node
    ADD CONSTRAINT node_label_key UNIQUE (label);

ALTER TABLE ONLY node
    ADD CONSTRAINT node_pkey PRIMARY KEY (node);

ALTER TABLE ONLY arc
    ADD CONSTRAINT arc_pred_fkey FOREIGN KEY (pred) REFERENCES node(node);

ALTER TABLE ONLY arc
    ADD CONSTRAINT arc_pkey PRIMARY KEY (ver);

ALTER TABLE ONLY arc
    ADD CONSTRAINT arc_replaces_fkey FOREIGN KEY (replaces) REFERENCES arc(ver);
