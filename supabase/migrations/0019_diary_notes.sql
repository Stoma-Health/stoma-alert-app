-- Stoma Alert — private diary notes
--
-- A note is not a check-in and not a photo caption. A check-in is four ratings
-- and a leak; a photo note describes an image. Neither has anywhere to put
-- "the curry was a mistake" or "ask the nurse about the flange size on Tuesday",
-- which is the thing patients actually want to write down between appointments.
--
-- PRIVATE means private. Unlike care_logs and care_tasks, there is no nurse
-- read policy here: the screen calls it a private note, so a clinician quietly
-- reading it would make the label a lie. If shared notes are wanted later that
-- is a different feature with a different word on the button.
--
-- Run in Supabase -> SQL Editor. Safe to re-run.

create table if not exists public.diary_notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title      text,
  body       text not null,
  created_at timestamptz not null default now()
);

-- The only query: this patient's notes, newest first.
create index if not exists diary_notes_user_created_idx
  on public.diary_notes (user_id, created_at desc);

alter table public.diary_notes enable row level security;

drop policy if exists "read own notes" on public.diary_notes;
create policy "read own notes" on public.diary_notes for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "insert own notes" on public.diary_notes;
create policy "insert own notes" on public.diary_notes for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "update own notes" on public.diary_notes;
create policy "update own notes" on public.diary_notes for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A private note you cannot delete is a worse thing to offer than no note.
drop policy if exists "delete own notes" on public.diary_notes;
create policy "delete own notes" on public.diary_notes for delete to authenticated
  using (user_id = auth.uid());
