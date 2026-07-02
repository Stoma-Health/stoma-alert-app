-- Stoma Alert — one-time patient profile (Part A of the self-interview sheet)
-- First name, stoma type, date of stoma creation, and the products the patient uses.
-- One row per patient (keyed by user_id). Run in Supabase → SQL Editor.

create table if not exists public.patient_profile (
  user_id        uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  patient_name   text,
  patient_email  text,
  stoma_type     text check (stoma_type in ('Ileostomy','Colostomy','Urostomy')),
  stoma_date     date,
  products       jsonb not null default '[]'::jsonb,
  updated_at     timestamptz not null default now()
);

alter table public.patient_profile enable row level security;

-- A patient may create/replace/read their own profile.
drop policy if exists "upsert own profile" on public.patient_profile;
create policy "upsert own profile"
  on public.patient_profile for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "update own profile" on public.patient_profile;
create policy "update own profile"
  on public.patient_profile for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- A patient sees their own; a nurse (role in their JWT) sees everyone's.
drop policy if exists "read own or all-if-nurse (profile)" on public.patient_profile;
create policy "read own or all-if-nurse (profile)"
  on public.patient_profile for select
  to authenticated
  using (
    user_id = auth.uid()
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
  );
