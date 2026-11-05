-- Go Dojo: the tables of the accounts. Paste it in Supabase, SQL Editor,
-- then Run. Each user only sees and changes their own rows.

-- The SGF files of the library, by path in the library ("folder/name.sgf").
-- A deleted file stays as a row with deleted = true, so the other devices
-- delete it too.
create table if not exists public.files (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  path text not null,
  sgf text,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, path)
);

-- The training progress of the global trainer (one JSON per user).
create table if not exists public.progress (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.files enable row level security;
alter table public.progress enable row level security;

drop policy if exists "own files" on public.files;
create policy "own files" on public.files
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "own progress" on public.progress;
create policy "own progress" on public.progress
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.files to authenticated;
grant select, insert, update, delete on public.progress to authenticated;
