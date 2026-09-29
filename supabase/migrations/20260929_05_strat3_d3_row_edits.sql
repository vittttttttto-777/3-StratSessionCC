-- День 3: правки строк матрицы на сессии — переименование, смена блока и типа, удаление и восстановление.
-- Правки хранятся в strat3_d3_docs (coll = 'edits', path = 'edits/p{№}'); исходная матрица в strat3_d3_processes не меняется.
alter table public.strat3_d3_docs drop constraint if exists strat3_d3_docs_coll_check;
alter table public.strat3_d3_docs add constraint strat3_d3_docs_coll_check check (coll in ('votes','dec','links','comments','extra','config','edits'));

create or replace view public.strat3_d3_row_edits with (security_invoker = true) as
select split_part(d.path,'/',2) as pid,
  case when split_part(d.path,'/',2) ~ '^p[0-9]+$' then substr(split_part(d.path,'/',2),2)::int end as process_id,
  d.data->'ru'->>'name' as name_ru, d.data->'en'->>'name' as name_en,
  d.data->>'type' as mgmt_type, d.data->>'block' as block,
  coalesce((d.data->>'deleted')::boolean,false) as deleted,
  to_timestamp((d.data->>'at')::bigint/1000.0) as updated_at
from public.strat3_d3_docs d where d.coll = 'edits';

drop view if exists public.strat3_d3_register;
create view public.strat3_d3_register with (security_invoker = true) as
with rows_ as (
  select 'p'||p.id as pid, p.id, coalesce(nullif(e.data->>'block',''),p.block) as block,
    coalesce(nullif(e.data->'ru'->>'dir',''),p.direction) as direction,
    coalesce(nullif(e.data->'ru'->>'name',''),p.name) as name,
    coalesce(nullif(e.data->'en'->>'name',''),p.en->>'name') as name_en,
    coalesce(nullif(e.data->>'type',''),p.mgmt_type) as mgmt_type,
    coalesce(nullif(e.data->'ru'->>'g',''),p.global_resp) as global_resp,
    coalesce(nullif(e.data->'ru'->>'l',''),p.local_resp) as local_resp,
    coalesce((e.data->>'deleted')::boolean,false) as deleted, false as added_at_session
  from public.strat3_d3_processes p
  left join public.strat3_d3_docs e on e.path = 'edits/p'||p.id
  union all
  select 'p'||(x.data->>'id'), null, coalesce(nullif(e.data->>'block',''),x.data->>'blockKey',x.data->>'block'),
    coalesce(nullif(e.data->'ru'->>'dir',''),x.data->>'dir'),
    coalesce(nullif(e.data->'ru'->>'name',''),x.data->>'name'),
    coalesce(nullif(e.data->'en'->>'name',''),x.data->>'name_en'),
    coalesce(nullif(e.data->>'type',''),x.data->>'type','Mix'),
    coalesce(nullif(e.data->'ru'->>'g',''),x.data->>'g'),
    coalesce(nullif(e.data->'ru'->>'l',''),x.data->>'l'),
    coalesce((e.data->>'deleted')::boolean,false), true
  from public.strat3_d3_docs x
  left join public.strat3_d3_docs e on e.path = 'edits/p'||(x.data->>'id')
  where x.coll = 'extra'
)
select r.pid, r.id, r.block, r.direction, r.name, r.name_en, r.mgmt_type, r.global_resp, r.local_resp, r.added_at_session,
  (select jsonb_object_agg(v.role, v.level) from public.strat3_d3_votes v where v.pid = r.pid and v.level is not null) as positions,
  (select count(*) from public.strat3_d3_votes v where v.pid = r.pid and v.star) as stars,
  dc.level as decision_level, dc.decided_by_role, dc.threshold, dc.hq_deadline, dc.metric, dc.rationale,
  coalesce(dc.status,'open') as status, dc.r11_owner, dc.r11_due,
  coalesce(
    (select array_agg(f.name order by x.ord) from public.strat3_d3_docs l
       cross join lateral jsonb_array_elements_text(l.data->'fx') with ordinality as x(fid, ord)
       join public.strat3_d3_functions f on f.id = x.fid
     where l.path = 'links/'||r.pid),
    (select array_agg(f.name order by pf.sort) from public.strat3_d3_process_functions pf
       join public.strat3_d3_functions f on f.id = pf.function_id where pf.process_id = r.id)
  ) as functions,
  (select count(*) from public.strat3_d3_comments c where c.pid = r.pid) as comments
from rows_ r
left join public.strat3_d3_decisions dc on dc.pid = r.pid
where not r.deleted
order by r.id nulls last, r.pid;
