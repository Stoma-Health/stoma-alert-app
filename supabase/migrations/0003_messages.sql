-- Stoma Alert — patient ↔ nurse messaging (test data only)
-- Run this in Supabase → SQL Editor. The thread is keyed by the PATIENT (thread_user).

create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  thread_user  uuid not null,                                  -- the patient the thread belongs to
  sender_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  sender_role  text not null,                                  -- 'patient' | 'nurse'
  sender_name  text,
  body         text not null,
  created_at   timestamptz not null default now()
);

create index if not exists messages_thread_idx on public.messages (thread_user, created_at);

alter table public.messages enable row level security;

-- A patient reads their own thread; a nurse reads every thread.
drop policy if exists "read own thread or nurse" on public.messages;
create policy "read own thread or nurse"
  on public.messages for select to authenticated
  using (
    thread_user = auth.uid()
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
  );

-- A patient writes into their own thread; a nurse writes into any thread.
drop policy if exists "send to own thread or nurse" on public.messages;
create policy "send to own thread or nurse"
  on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      thread_user = auth.uid()
      or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
    )
  );

-- Enable realtime so the other side sees new messages without refreshing.
alter publication supabase_realtime add table public.messages;
