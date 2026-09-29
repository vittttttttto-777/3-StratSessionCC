-- Стратсессия №3, день 3: справочные таблицы матрицы и табличные представления состояния сессии
create table if not exists public.strat3_d3_functions (
  id text primary key, sort int not null, name text not null, sub text, kind text,
  tasks jsonb not null default '[]', extra jsonb not null default '[]',
  zone text, conflicts text, owner text, reports text, decides text, veto text,
  en jsonb not null default '{}', updated_at timestamptz not null default now()
);
create table if not exists public.strat3_d3_processes (
  id int primary key, block text not null, direction text, function_text text, name text not null,
  mgmt_type text not null check (mgmt_type in ('Global','Local','Mix')),
  global_resp text, local_resp text, approval_note text, kpi text, priority numeric,
  audience text, regularity text, data_sources text,
  en jsonb not null default '{}',
  source text not null default 'Матрица «Красные линии», 23.09.2026',
  updated_at timestamptz not null default now()
);
create table if not exists public.strat3_d3_process_functions (
  process_id int not null references public.strat3_d3_processes(id) on delete cascade,
  function_id text not null references public.strat3_d3_functions(id) on delete cascade,
  sort int not null default 0,
  primary key (process_id, function_id)
);
alter table public.strat3_d3_functions enable row level security;
alter table public.strat3_d3_processes enable row level security;
alter table public.strat3_d3_process_functions enable row level security;
create policy "d3 functions read" on public.strat3_d3_functions for select to anon, authenticated using (true);
create policy "d3 processes read" on public.strat3_d3_processes for select to anon, authenticated using (true);
create policy "d3 process functions read" on public.strat3_d3_process_functions for select to anon, authenticated using (true);

create or replace view public.strat3_d3_votes with (security_invoker = true) as
select case when d.data->>'pid' ~ '^p[0-9]+$' then substr(d.data->>'pid',2)::int end as process_id,
  d.data->>'pid' as pid, d.data->>'role' as role, d.data->>'level' as level,
  coalesce((d.data->>'star')::boolean,false) as star, to_timestamp((d.data->>'at')::bigint/1000.0) as voted_at
from public.strat3_d3_docs d where d.coll = 'votes';

create or replace view public.strat3_d3_decisions with (security_invoker = true) as
select case when split_part(d.path,'/',2) ~ '^p[0-9]+$' then substr(split_part(d.path,'/',2),2)::int end as process_id,
  split_part(d.path,'/',2) as pid, d.data->>'level' as level, d.data->>'who' as decided_by_role,
  d.data->>'thr' as threshold, d.data->>'sla' as hq_deadline, d.data->>'metric' as metric, d.data->>'note' as rationale,
  d.data->>'status' as status, d.data->>'owner' as r11_owner, d.data->>'due' as r11_due,
  to_timestamp((d.data->>'at')::bigint/1000.0) as updated_at
from public.strat3_d3_docs d where d.coll = 'dec';

create or replace view public.strat3_d3_comments with (security_invoker = true) as
select d.data->>'id' as id, case when d.data->>'pid' ~ '^p[0-9]+$' then substr(d.data->>'pid',2)::int end as process_id,
  d.data->>'pid' as pid, d.data->>'kind' as kind, d.data->>'role' as role, d.data->>'text' as text,
  to_timestamp((d.data->>'at')::bigint/1000.0) as created_at
from public.strat3_d3_docs d where d.coll = 'comments';

create or replace view public.strat3_d3_register with (security_invoker = true) as
select p.id, p.block, p.direction, p.name, p.mgmt_type, p.global_resp, p.local_resp,
  (select jsonb_object_agg(v.role, v.level) from public.strat3_d3_votes v where v.process_id = p.id and v.level is not null) as positions,
  (select count(*) from public.strat3_d3_votes v where v.process_id = p.id and v.star) as stars,
  dc.level as decision_level, dc.decided_by_role, dc.threshold, dc.hq_deadline, dc.metric, dc.rationale,
  coalesce(dc.status, 'open') as status, dc.r11_owner, dc.r11_due,
  coalesce(
    (select array_agg(f.name order by x.ord) from public.strat3_d3_docs l
       cross join lateral jsonb_array_elements_text(l.data->'fx') with ordinality as x(fid, ord)
       join public.strat3_d3_functions f on f.id = x.fid
     where l.path = 'links/p' || p.id),
    (select array_agg(f.name order by pf.sort) from public.strat3_d3_process_functions pf
       join public.strat3_d3_functions f on f.id = pf.function_id where pf.process_id = p.id)
  ) as functions,
  (select count(*) from public.strat3_d3_comments c where c.process_id = p.id) as comments
from public.strat3_d3_processes p
left join public.strat3_d3_decisions dc on dc.process_id = p.id
order by p.id;
