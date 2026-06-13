-- Stoma Alert — prototype schema (test data only; not for real patients)
-- Run this in Supabase → SQL Editor, or let the GitHub integration apply it.

create table if not exists public.check_ins (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  patient_name  text,
  patient_email text,
  output        int  check (output  between 1 and 5),
  skin          int  check (skin    between 1 and 5),
  comfort       int  check (comfort  between 1 and 5),
  mood          int  check (mood     between 1 and 5),
  note          text,
  created_at    timestamptz not null default now()
);

create index if not exists check_ins_user_id_created_idx
  on public.check_ins (user_id, created_at desc);

alter table public.check_ins enable row level security;

-- A patient may insert their own check-ins.
drop policy if exists "insert own check-ins" on public.check_ins;
create policy "insert own check-ins"
  on public.check_ins for insert
  to authenticated
  with check (user_id = auth.uid());

-- A patient sees their own; a nurse (role in their JWT) sees everyone's.
drop policy if exists "read own or all-if-nurse" on public.check_ins;
create policy "read own or all-if-nurse"
  on public.check_ins for select
  to authenticated
  using (
    user_id = auth.uid()
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
  );
