-- Stoma Alert — reorder reminders by date
--
-- The cupboard originally worked on a running count: say how many you have,
-- say what number to nudge you at, and adjust it with + and - as you use them.
-- That asks a patient to maintain an inventory. People do not, and the one week
-- they are least likely to keep it up is the week they most need the prompt.
--
-- So the question changes from "how many do you have" to "when do you want to
-- be reminded". A date is set once, by the person who knows their own delivery
-- rhythm, and it does not decay if nobody touches it.
--
-- quantity and reorder_at are KEPT, not dropped. Existing cupboards have real
-- numbers in them and dropping the columns would destroy that record for the
-- sake of a screen that no longer shows it. They are simply no longer read.
--
-- Run in Supabase -> SQL Editor. Safe to re-run.

alter table public.supply_items
  add column if not exists remind_on date;

comment on column public.supply_items.remind_on is
  'When the patient asked to be reminded to reorder. NULL = no reminder set; the row still lists, it just never prompts.';

-- The only question asked of this column: what is due today or overdue.
create index if not exists supply_items_remind_idx
  on public.supply_items (user_id, remind_on)
  where remind_on is not null;

-- The "running low" view becomes "due to reorder". Same name so nothing else
-- has to change, and the rule still lives in exactly one place.
--
-- Dropped and recreated rather than CREATE OR REPLACE: the column list changes
-- (short_by goes, remind_on and days_overdue arrive) and Postgres will not
-- replace a view whose columns have been renamed or removed. Nothing depends on
-- this view except one count query in the app, so dropping it costs nothing.
--
-- NULL remind_on is excluded on purpose: a row with no reminder is not overdue,
-- it is unset, and treating the two the same would make the home badge cry wolf
-- on every item anyone ever added.
drop view if exists public.supply_items_low;
create view public.supply_items_low
  with (security_invoker = true) as
  select id, user_id, name, product_code, supplier, quantity, reorder_at, unit,
         remind_on, updated_at,
         (current_date - remind_on) as days_overdue
    from public.supply_items
   where remind_on is not null
     and remind_on <= current_date;
