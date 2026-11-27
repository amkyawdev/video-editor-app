-- Movie Recap Studio: profiles, projects, preferences and job metadata.
-- Large media never lives in Postgres; only metadata and storage paths.
create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  locale text not null default 'en',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  canvas_width int not null default 1920 check (canvas_width between 16 and 8192),
  canvas_height int not null default 1080 check (canvas_height between 16 and 8192),
  fps numeric(6,3) not null default 30,
  duration_ms bigint not null default 0 check (duration_ms >= 0),
  local_path text,
  cover_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.preferences (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  theme text not null default 'dark' check (theme in ('dark','light','system')),
  app_language text not null default 'en',
  target_language text not null default 'my',
  output_folder text,
  ai_provider text,
  worker_url text,
  updated_at timestamptz not null default now()
);

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  kind text not null check (kind in ('import','probe','recap','translate','render','export')),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','cancelled')),
  progress real not null default 0 check (progress >= 0 and progress <= 1),
  message text,
  output_path text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.preferences enable row level security;
alter table public.jobs enable row level security;

create policy "profiles_select_own" on public.profiles for select using (auth.uid() = id);
create policy "profiles_upsert_own" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "projects_owner_all" on public.projects for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "preferences_owner_all" on public.preferences for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "jobs_owner_all" on public.jobs for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create index if not exists projects_owner_updated_idx on public.projects(owner_id, updated_at desc);
create index if not exists jobs_owner_created_idx on public.jobs(owner_id, created_at desc);

-- Keep updated_at fresh.
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists projects_touch on public.projects;
create trigger projects_touch before update on public.projects for each row execute function public.touch_updated_at();
drop trigger if exists preferences_touch on public.preferences;
create trigger preferences_touch before update on public.preferences for each row execute function public.touch_updated_at();
