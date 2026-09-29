-- День 3: вход по паролю участника (тот же пароль, что во второй день).
-- Страница зашифрована AES-GCM; ключ расшифровки хранится только здесь и выдаётся функцией при верном пароле.
-- Ключ не хранится в репозитории: подставьте его вместо <CONTENT_KEY> при развёртывании в новом проекте.
create table if not exists public.strat3_d3_secret (
  id int primary key default 1 check (id = 1),
  pass_hash text not null,
  content_key text not null,
  updated_at timestamptz not null default now()
);
alter table public.strat3_d3_secret enable row level security;
revoke all on public.strat3_d3_secret from anon, authenticated;
insert into public.strat3_d3_secret (id, pass_hash, content_key)
select 1, pass_hash, '<CONTENT_KEY>' from public.strat3_d2_secret where id = 1
on conflict (id) do nothing;
create or replace function public.strat3_d3_unlock(p_pass text)
returns text language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare k text;
begin
  select content_key into k from public.strat3_d3_secret
   where id = 1 and pass_hash = encode(extensions.digest(coalesce(p_pass, ''), 'sha256'), 'hex');
  if k is null then perform pg_sleep(0.6); end if;
  return k;
end $$;
revoke all on function public.strat3_d3_unlock(text) from public;
grant execute on function public.strat3_d3_unlock(text) to anon, authenticated;
-- Сменить пароль:
-- update public.strat3_d3_secret set pass_hash = encode(extensions.digest('новый пароль','sha256'),'hex'), updated_at = now() where id = 1;
