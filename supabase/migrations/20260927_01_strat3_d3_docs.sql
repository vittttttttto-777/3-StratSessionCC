-- Стратсессия №3, день 3: живое состояние сессии (позиции, решения, привязки функций, комментарии, настройки)
create table if not exists public.strat3_d3_docs (
  path text primary key check (char_length(path) <= 200),
  coll text not null check (coll in ('votes','dec','links','comments','extra','config')),
  data jsonb not null check (pg_column_size(data) < 65536),
  updated_at timestamptz not null default now()
);
create table if not exists public.strat3_d3_history (
  id bigserial primary key, path text not null, op text not null, data jsonb, at timestamptz not null default now()
);
alter table public.strat3_d3_docs enable row level security;
alter table public.strat3_d3_history enable row level security;
create policy "d3 read" on public.strat3_d3_docs for select to anon, authenticated using (true);
create policy "d3 insert" on public.strat3_d3_docs for insert to anon, authenticated with check (split_part(path,'/',1) = coll);
create policy "d3 update" on public.strat3_d3_docs for update to anon, authenticated using (true) with check (split_part(path,'/',1) = coll);
create policy "d3 delete" on public.strat3_d3_docs for delete to anon, authenticated using (coll in ('votes','comments','links'));
create or replace function public.strat3_d3_log() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    insert into public.strat3_d3_history(path, op, data) values (old.path, 'delete', old.data);
    return old;
  end if;
  new.updated_at := now();
  insert into public.strat3_d3_history(path, op, data) values (new.path, lower(tg_op), new.data);
  return new;
end $$;
revoke all on function public.strat3_d3_log() from public, anon, authenticated;
create trigger strat3_d3_log_trg before insert or update or delete on public.strat3_d3_docs for each row execute function public.strat3_d3_log();
alter publication supabase_realtime add table public.strat3_d3_docs;
alter table public.strat3_d3_docs replica identity full;
