-- Stoma Alert — detailed care logs + care plan tasks
--
-- The last two ideas worth taking from the stomaalertapp prototype. As with
-- 0017, the data model travels and the code does not: theirs has no row-level
-- security and takes identity from a spoofable header.
--
-- 1) CARE LOGS are not check-ins. A check-in is four 1-5 ratings and takes a
--    minute; it is the thing we ask for daily and must stay short. A care log
--    is the detailed record a nurse actually needs when something is wrong:
--    measured output, hydration, consistency, pain, leaks, pouch changes, food.
--    Keeping them in separate tables keeps the daily ask small, which is the
--    only reason anyone completes it.
--
--    High output is the thing this exists to catch. Roughly 1500ml/day is where
--    dehydration and electrolyte loss become a genuine clinical concern for an
--    ileostomy, so the figure is recorded in millilitres rather than a 1-5
--    feeling. It is recorded and shown, never interpreted: this app does not
--    diagnose, and a threshold in a database is not a clinical judgement.
--
-- 2) CARE TASKS are the care plan: things with a due date that can be ticked.
--
-- Run in Supabase → SQL Editor. Safe to re-run.

-- =========================================================== care logs
create table if not exists public.care_logs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  output_ml     int  check (output_ml between 0 and 10000),
  hydration_ml  int  check (hydration_ml between 0 and 20000),
  consistency   text check (consistency in ('Liquid','Porridge','Thick','Formed')),
  skin_status   text check (skin_status in ('Healthy','Pink','Red','Broken')),
  pain          int  check (pain between 0 and 10),
  leak          boolean,
  pouch_changed int  check (pouch_changed between 0 and 20),
  food          text,
  symptoms      text,
  created_at    timestamptz not null default now()
);

create index if not exists care_logs_user_created_idx
  on public.care_logs (user_id, created_at desc);

-- The query a nurse runs: show me the high-output days.
create index if not exists care_logs_high_output_idx
  on public.care_logs (user_id, created_at desc)
  where output_ml >= 1500;

alter table public.care_logs enable row level security;

drop policy if exists "read own care logs or nurse" on public.care_logs;
create policy "read own care logs or nurse" on public.care_logs for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());

drop policy if exists "insert own care logs" on public.care_logs;
create policy "insert own care logs" on public.care_logs for insert to authenticated
  with check (user_id = auth.uid());

-- Patients may correct their own entry. Nurses may not: an edited record with
-- no author is worse than no record.
drop policy if exists "update own care logs" on public.care_logs;
create policy "update own care logs" on public.care_logs for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "delete own care logs" on public.care_logs;
create policy "delete own care logs" on public.care_logs for delete to authenticated
  using (user_id = auth.uid());

-- =========================================================== care tasks
create table if not exists public.care_tasks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category   text not null default 'General',
  title      text not null,
  detail     text,
  due_date   date,
  completed  boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists care_tasks_user_due_idx
  on public.care_tasks (user_id, completed, due_date);

alter table public.care_tasks enable row level security;

-- Nurses CAN write here, unlike everywhere else, because setting a task is
-- exactly what a care plan is for. They cannot delete one: a task that was set
-- and then vanished is a gap in the record.
drop policy if exists "read own tasks or nurse" on public.care_tasks;
create policy "read own tasks or nurse" on public.care_tasks for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());

drop policy if exists "insert own tasks or nurse" on public.care_tasks;
create policy "insert own tasks or nurse" on public.care_tasks for insert to authenticated
  with check (user_id = auth.uid() or public.is_nurse());

drop policy if exists "update own tasks or nurse" on public.care_tasks;
create policy "update own tasks or nurse" on public.care_tasks for update to authenticated
  using (user_id = auth.uid() or public.is_nurse())
  with check (user_id = auth.uid() or public.is_nurse());

drop policy if exists "delete own tasks" on public.care_tasks;
create policy "delete own tasks" on public.care_tasks for delete to authenticated
  using (user_id = auth.uid());
