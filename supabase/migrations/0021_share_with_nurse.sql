-- Stoma Alert — patient-controlled sharing
--
-- The home screen promises "YOU CONTROL WHAT IS SHARED". Until now that was only
-- true of the diary, which no clinician could read, and untrue of the daily care
-- log, which every nurse could read in full. This migration makes the promise
-- literal: personal content is shared by choice, the clinical check-in stays
-- shared by design.
--
--   check_ins   unchanged. Four ratings and a leak, submitted for review. That is
--               what the app is for, and a check-in a nurse cannot see is not a
--               check-in. Making these optional would gut the clinical purpose.
--   care_logs   nurses previously read every row. Now they read only rows the
--               patient shared. This REMOVES access that existed before 0021.
--   diary_notes gains a nurse read path for the first time, but only for rows the
--               patient shared. 0019 said a shared note would be "a different
--               feature with a different word on the button". This is that
--               feature, and the button says Share with nurse.
--   supply_items and care_tasks unchanged. A cupboard is stock control, not a
--               confidence, and a reminder is a shared plan by definition.
--
-- Existing rows default to NOT shared. Nobody consented to sharing them, so
-- inheriting consent would be the wrong way round, even on test data.
--
-- Run in Supabase -> SQL Editor. Safe to re-run.

begin;

-- ------------------------------------------------------------------ care logs
alter table public.care_logs
  add column if not exists shared_with_nurse boolean not null default false;

-- The nurse-side query: this patient's shared rows, newest first.
create index if not exists care_logs_shared_idx
  on public.care_logs (user_id, created_at desc)
  where shared_with_nurse;

drop policy if exists "read own care logs or nurse" on public.care_logs;
drop policy if exists "read own care logs or shared with nurse" on public.care_logs;
create policy "read own care logs or shared with nurse" on public.care_logs
  for select to authenticated
  using (user_id = auth.uid() or (public.is_nurse() and shared_with_nurse));

-- Only the patient may change the sharing flag. The update policy already
-- restricts writes to the owner, so a nurse cannot share a log on their behalf.

-- ---------------------------------------------------------------- diary notes
alter table public.diary_notes
  add column if not exists shared_with_nurse boolean not null default false;

create index if not exists diary_notes_shared_idx
  on public.diary_notes (user_id, created_at desc)
  where shared_with_nurse;

drop policy if exists "read own notes" on public.diary_notes;
drop policy if exists "read own notes or shared with nurse" on public.diary_notes;
create policy "read own notes or shared with nurse" on public.diary_notes
  for select to authenticated
  using (user_id = auth.uid() or (public.is_nurse() and shared_with_nurse));

-- Writes stay owner-only, unchanged from 0019: insert, update and delete all
-- test user_id = auth.uid(), so sharing is always the patient's own act and
-- can always be taken back.

commit;
