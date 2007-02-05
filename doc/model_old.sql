CREATE SEQUENCE node_seq;
CREATE TABLE reltype (
    id integer NOT NULL,
    label text NOT NULL,
    valtype character varying(10),
    "comment" text,
    domain_is integer,
    domain_scof integer,
    range_is integer,
    range_scof integer
);
CREATE TABLE rel (
    id integer DEFAULT nextval('node_seq'::text) NOT NULL,
    sub integer NOT NULL,
    pred integer NOT NULL,
    obj integer,
    valdate timestamp with time zone,
    valtext text,
    valclean text,
    valint integer,
    valfloat double precision,
    updated timestamp with time zone DEFAULT now(),
    updated_by integer,
    indirect boolean DEFAULT false,
    "implicit" boolean DEFAULT false
);
CREATE SEQUENCE reltype_seq;
CREATE TABLE syllogism (
    id integer DEFAULT nextval('node_seq'::text) NOT NULL,
    a integer NOT NULL,
    b integer NOT NULL,
    c integer NOT NULL
);
CREATE TABLE constant (
    sub integer NOT NULL,
    label character varying(64) NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    updated_by integer NOT NULL
);
COPY reltype (id, label, valtype, "comment", domain_is, domain_scof, range_is, range_scof) FROM s
tdin;
1       is      obj     \N      \N      \N      \N      \N
2       scof    obj     \N      \N      \N      \N      \N
4	value	value	\N	\N	\N	\N	\N
11      name    text    \N      \N      \N      \N      \N
12	description	textbox	\N      \N      \N      \N      \N
14      name_short      text    \N      \N      \N      \N      \N
15      language        obj     \N      \N      \N      \N      \N
16	code	text	\N      \N      \N      \N      \N
21      created date    \N      \N      \N      \N      \N
22      updated date    \N      \N      \N      \N      \N
31	note	text	\N      \N      \N      \N      \N
102	password	password	\N      \N      \N      \N      \N
103     has_access_right        obj     \N      \N      \N      \N      \N
302	weight	int	\N      \N      \N      \N      \N
307	datatype	obj	\N      \N      \N      \N      \N
\.

COPY constant (sub, label, updated, updated_by) FROM stdin;
1105    login_account   2006-07-17 15:57:53+02  1115
1106    intelligent_agent       2006-07-17 15:57:53+02  1115
1116    full_access     2006-07-17 15:57:53+02  1115
1117    language        2006-07-17 15:57:53+02  1115
2001	guest_access    2006-07-17 15:57:53+02  1115
2002	literal 2006-07-17 15:57:53+02  1115
2003	webpage 2006-07-17 15:57:53+02  1115
2004 	person  2006-07-17 15:57:53+02  1115
2005	class   2006-10-04 16:39:43.918294+02   1115
\.

COPY syllogism (id, a, b, c) FROM stdin;
1084483 1       2       1
1084484 2       2       2
\.


CREATE INDEX reltype_label_idx ON reltype USING btree (label);
CREATE INDEX rel_sub_idx ON rel USING btree (sub);
CREATE INDEX rel_obj_idx ON rel USING btree (obj);
CREATE INDEX rel_pred_obj_idx ON rel USING btree (pred, obj);
CREATE INDEX rel_pred_clean_idx ON rel USING btree (pred, valclean);
CREATE INDEX rel_pred_int_idx ON rel USING btree (pred, valint);
CREATE INDEX rel_sub_pred_idx ON rel USING btree (sub, pred);
CREATE INDEX rel_pred_idx ON rel USING btree (pred);


CREATE UNIQUE INDEX constant_label_idx ON constant USING btree (label);
CREATE INDEX rel_pred_text_idx ON rel USING btree (pred, valtext);


ALTER TABLE ONLY reltype
    ADD CONSTRAINT reltype_pkey PRIMARY KEY (id);


ALTER TABLE ONLY rel
    ADD CONSTRAINT rel_pkey PRIMARY KEY (id);


ALTER TABLE ONLY syllogism
    ADD CONSTRAINT syllogism_pkey PRIMARY KEY (id);


ALTER TABLE ONLY constant
    ADD CONSTRAINT constant_pkey PRIMARY KEY (sub);


SELECT pg_catalog.setval('node_seq', 4142655, true);


SELECT pg_catalog.setval('reltype_seq', 354, true);

