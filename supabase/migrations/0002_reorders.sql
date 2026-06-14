-- Stoma Alert — supply reorder requests (test data only)
-- Run this in Supabase → SQL Editor.

create table if not exists public.reorders (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  patient_name  text,
  patient_email text,
  item          text not null default 'Drainable pouch · 60mm',
  status        text not null default 'requested',
  created_at    timestamptz not null default now()
);

create index if not exists reorders_user_created_idx
  on public.reorders (user_id, created_at desc);

alter table public.reorders enable row level security;

-- A patient may request their own reorders.
drop policy if exists "insert own reorders" on public.reorders;
create policy "insert own reorders"
  on public.reorders for insert
  to authenticated
  with check (user_id = auth.uid());

-- A patient sees their own; a nurse (role in their JWT) sees everyone's.
drop policy if exists "read own or all-if-nurse reorders" on public.reorders;
create policy "read own or all-if-nurse reorders"
  on public.reorders for select
  to authenticated
  using (
    user_id = auth.uid()
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
  );
