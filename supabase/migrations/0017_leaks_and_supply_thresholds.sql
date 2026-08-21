-- Stoma Alert — leak tracking + supply reorder thresholds
--
-- Both ideas come from the ChatGPT-built `stomaalertapp` prototype, which had a
-- richer data model than ours. Ported deliberately rather than wholesale: its
-- schema has no row-level security and its identity comes from a spoofable
-- request header, so the ideas travel and the code does not.
--
-- Two additions:
--
-- 1) LEAKS on a check-in. A leak is the event patients actually organise their
--    day around, and it is the one thing a nurse wants to know happened without
--    reading a paragraph. It is a boolean, and it is NULLABLE on purpose:
--    existing check-ins were taken before the question was ever asked, and
--    backfilling them to false would be inventing clinical data. null means
--    "not asked", false means "asked, and no", and the difference matters if
--    anyone ever counts leaks per month.
--
-- 2) SUPPLY ITEMS with a reorder threshold. "Reorder" as a button requires the
--    patient to notice they are running low, which is exactly the thing that
--    fails in the week they feel worst. A threshold turns it into the app
--    noticing. Quantities are patient-maintained, so this is a prompt, not an
--    inventory system, and it must not be presented as stock control.
--
-- Run in Supabase → SQL Editor. Safe to re-run.

-- =========================================================== 1. leaks
alter table public.check_ins
  add column if not exists leak boolean;

comment on column public.check_ins.leak is
  'Leak since the last check-in. NULL = not asked (pre-2026-08 rows); false = asked and none.';

-- Partial index: the only query anyone runs is "show me the leaks", and leaks
-- should be the minority of rows. Indexing just the true ones keeps it small.
create index if not exists check_ins_leaks_idx
  on public.check_ins (user_id, created_at desc)
  where leak is true;

-- =========================================================== 2. supply items
create table if not exists public.supply_items (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name         text not null,
  product_code text,
  supplier     text,
  quantity     int  not null default 0 check (quantity >= 0),
  reorder_at   int  not null default 5 check (reorder_at >= 0),
  unit         text not null default 'box',
  updated_at   timestamptz not null default now()
);

create index if not exists supply_items_user_idx
  on public.supply_items (user_id, name);

-- The whole point of the feature: what is at or below its threshold.
create index if not exists supply_items_low_idx
  on public.supply_items (user_id)
  where quantity <= reorder_at;

alter table public.supply_items enable row level security;

-- Patients own their own list outright. Nurses and admins read, never write:
-- a nurse editing a patient's cupboard count would be a record of something
-- they cannot see.
drop policy if exists "read own supply items" on public.supply_items;
create policy "read own supply items" on public.supply_items for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());

drop policy if exists "insert own supply items" on public.supply_items;
create policy "insert own supply items" on public.supply_items for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "update own supply items" on public.supply_items;
create policy "update own supply items" on public.supply_items for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "delete own supply items" on public.supply_items;
create policy "delete own supply items" on public.supply_items for delete to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------------------------- low stock view
-- A view so the "running low" rule lives in one place. security_invoker means
-- it is read through the caller's own policies rather than the view owner's,
-- so it cannot become a way around RLS.
create or replace view public.supply_items_low
  with (security_invoker = true) as
  select id, user_id, name, product_code, supplier, quantity, reorder_at, unit,
         updated_at,
         (reorder_at - quantity) as short_by
    from public.supply_items
   where quantity <= reorder_at;

-- --------------------------------------------------------------- updated_at
create or replace function public.touch_supply_item() returns trigger
  language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists supply_items_touch on public.supply_items;
create trigger supply_items_touch before update on public.supply_items
  for each row execute function public.touch_supply_item();
