-- Stoma Alert — education guide completion (test data only)
-- Run this in Supabase → SQL Editor. Content lives in the app; this just tracks who finished what.

create table if not exists public.guide_progress (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  guide_id     text not null,
  completed_at timestamptz not null default now(),
  unique (user_id, guide_id)
);

alter table public.guide_progress enable row level security;

-- A patient sees their own progress; a nurse can see everyone's (for engagement views later).
drop policy if exists "read own progress or nurse" on public.guide_progress;
create policy "read own progress or nurse"
  on public.guide_progress for select to authenticated
  using (
    user_id = auth.uid()
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
  );

drop policy if exists "mark own progress" on public.guide_progress;
create policy "mark own progress"
  on public.guide_progress for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "unmark own progress" on public.guide_progress;
create policy "unmark own progress"
  on public.guide_progress for delete to authenticated
  using (user_id = auth.uid());
