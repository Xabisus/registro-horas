-- =====================================================================
--  Registro de horas · esquema de Supabase
--  Pégalo entero en Supabase > SQL Editor > New query > Run.
--  ANTES de ejecutarlo, cambia TU-CORREO@EJEMPLO.COM (casi al final)
--  por el correo del primer administrador.
-- =====================================================================

-- ---------- tablas ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  name       text not null default '',
  role       text not null default 'member' check (role in ('admin', 'member')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- Solo los correos de esta lista pueden crear cuenta.
create table if not exists public.allowed_emails (
  email      text primary key check (email = lower(email)),
  role       text not null default 'member' check (role in ('admin', 'member')),
  created_at timestamptz not null default now()
);

create table if not exists public.workspace_settings (
  id   int primary key check (id = 1),
  data jsonb not null default '{}'::jsonb
);

create table if not exists public.clients (
  id       text primary key,
  name     text not null,
  address  text not null default '',
  archived boolean not null default false
);

create table if not exists public.projects (
  id        text primary key,
  name      text not null,
  client_id text references public.clients(id) on delete set null,
  color     text not null default '#2a78d6',
  billable  boolean not null default false,
  archived  boolean not null default false
);

create table if not exists public.tags (
  id       text primary key,
  name     text not null,
  archived boolean not null default false
);

create table if not exists public.time_entries (
  id         text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  text       text not null default '',
  done       boolean not null default false,
  start_at   timestamptz not null,
  end_at     timestamptz not null check (end_at > start_at),
  project_id text references public.projects(id) on delete set null,
  tag_ids    text[] not null default '{}',
  billable   boolean not null default false
);
create index if not exists time_entries_start_idx on public.time_entries (start_at);
create index if not exists time_entries_user_idx  on public.time_entries (user_id);

-- Cronómetro en marcha de cada persona (una fila por usuario).
create table if not exists public.running_timers (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  data    jsonb not null
);

-- ---------- funciones auxiliares ----------
create or replace function public.is_active()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active)
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin')
$$;

-- Al crear una cuenta: solo se permite si el correo está en allowed_emails.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  invite public.allowed_emails%rowtype;
begin
  select * into invite from public.allowed_emails where email = lower(new.email);
  if not found then
    raise exception 'Correo no autorizado';
  end if;
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    lower(new.email),
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1)),
    invite.role
  );
  return new;
end $$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- seguridad (RLS) ----------
alter table public.profiles           enable row level security;
alter table public.allowed_emails     enable row level security;
alter table public.workspace_settings enable row level security;
alter table public.clients            enable row level security;
alter table public.projects           enable row level security;
alter table public.tags               enable row level security;
alter table public.time_entries       enable row level security;
alter table public.running_timers     enable row level security;

-- profiles: todos los activos ven a todos; solo el admin cambia roles/estado
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (public.is_active() or id = auth.uid());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- allowed_emails: solo admin
drop policy if exists allowed_all on public.allowed_emails;
create policy allowed_all on public.allowed_emails for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ajustes: todos leen, solo admin escribe
drop policy if exists settings_select on public.workspace_settings;
create policy settings_select on public.workspace_settings for select to authenticated using (public.is_active());
drop policy if exists settings_insert on public.workspace_settings;
create policy settings_insert on public.workspace_settings for insert to authenticated with check (public.is_admin());
drop policy if exists settings_update on public.workspace_settings;
create policy settings_update on public.workspace_settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- clientes, proyectos, etiquetas: todos leen y editan, solo admin borra
do $$
declare t text;
begin
  foreach t in array array['clients', 'projects', 'tags'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active())', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.is_active())', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.is_active()) with check (public.is_active())', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.is_admin())', t || '_delete', t);
  end loop;
end $$;

-- horas: todos ven todo; cada persona edita solo las suyas (el admin, todas)
drop policy if exists entries_select on public.time_entries;
create policy entries_select on public.time_entries for select to authenticated using (public.is_active());
drop policy if exists entries_insert on public.time_entries;
create policy entries_insert on public.time_entries for insert to authenticated
  with check (public.is_active() and (user_id = auth.uid() or public.is_admin()));
drop policy if exists entries_update on public.time_entries;
create policy entries_update on public.time_entries for update to authenticated
  using (public.is_active() and (user_id = auth.uid() or public.is_admin()))
  with check (public.is_active() and (user_id = auth.uid() or public.is_admin()));
drop policy if exists entries_delete on public.time_entries;
create policy entries_delete on public.time_entries for delete to authenticated
  using (public.is_active() and (user_id = auth.uid() or public.is_admin()));

-- cronómetro: cada persona solo el suyo
drop policy if exists timers_all on public.running_timers;
create policy timers_all on public.running_timers for all to authenticated
  using (user_id = auth.uid() and public.is_active())
  with check (user_id = auth.uid() and public.is_active());

-- ---------- datos iniciales ----------
insert into public.workspace_settings (id, data) values (1, '{}'::jsonb) on conflict do nothing;

-- >>> CAMBIA ESTE CORREO por el del primer administrador <<<
insert into public.allowed_emails (email, role)
values (lower('TU-CORREO@EJEMPLO.COM'), 'admin')
on conflict (email) do nothing;
