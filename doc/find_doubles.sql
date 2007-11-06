
select CASE WHEN obj is not null THEN (select valtext from arc where pred=4 and subj=main.obj and active is true) ELSE valtext END as name, subj from arc as main where pred=11 and active is true and subj in ( select node from ( select subj as node from arc where pred=1 and (obj = '1103') and active is true ) as main         where exists ( select 1 from arc where subj=main.node and pred=121 and (obj = '1125') and active is true ) ) order by name;



