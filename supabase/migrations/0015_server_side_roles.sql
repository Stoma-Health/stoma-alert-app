-- Stoma Alert — server-enforced roles
--
-- WHAT WAS WRONG
-- Every policy in this schema decided who you were by reading
--   auth.jwt() -> 'user_metadata' ->> 'role'
-- In Supabase, user_metadata is writable BY THE USER. A patient who signed up
-- honestly could open the browser console and run
--   supabase.auth.updateUser({ data: { role: 'nurse' } })
-- and immediately read every other patient's check-ins, stoma photos, messages
-- and profile. The role was also simply chosen from three buttons at sign-up.
-- That is special-category health data under UK GDPR Art. 9.
--
-- THE FIX
-- Roles move into a table the user cannot write, and every policy asks that
-- table instead of the token. user_metadata is now decoration: changing it
-- grants nothing.
--
-- Run in Supabase → SQL Editor. Safe to re-run.

-- ---------------------------------------------------------------- roles table
create table if not exists public.user_roles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  role        text not null default 'patient' check (role in ('patient','nurse','admin')),
  assigned_at timestamptz not null default now(),
  assigned_by uuid references auth.users(id)
);

alter table public.user_roles enable row level security;

-- You may read your own role, so the app can render the right screens. Nothing
-- else. There is deliberately NO insert/update/delete policy: with RLS on, the
-- absence of a policy is a denial. Roles are granted out of band (see bottom).
drop policy if exists "read own role" on public.user_roles;
create policy "read own role" on public.user_roles for select to authenticated
  using (user_id = auth.uid());

-- Belt and braces: even if a policy is added carelessly later, the grant is gone.
revoke insert, update, delete on public.user_roles from authenticated, anon;
grant select on public.user_roles to authenticated;

-- ------------------------------------------------------------ role of caller
-- SECURITY DEFINER so it can read user_roles regardless of the caller, STABLE
-- so the planner may cache it within a statement, and search_path pinned so a
-- caller cannot shadow `user_roles` with something of their own.
create or replace function public.app_role() returns text
  language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select role from public.user_roles where user_id = auth.uid()), 'patient')
$$;

create or replace function public.is_nurse() returns boolean
  language sql stable security definer set search_path = public, pg_temp as $$
  select public.app_role() in ('nurse','admin')
$$;

create or replace function public.is_admin() returns boolean
  language sql stable security definer set search_path = public, pg_temp as $$
  select public.app_role() = 'admin'
$$;

grant execute on function public.app_role(), public.is_nurse(), public.is_admin()
  to authenticated;

-- ------------------------------------------------- everyone starts as patient
-- The role is assigned by the database, not by whatever the sign-up form sent.
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.user_roles (user_id, role) values (new.id, 'patient')
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------ backfill
-- EVERY existing account becomes a patient. Deliberately.
--
-- The obvious backfill is to copy each user's existing metadata role across.
-- Do not: that field is the one an attacker controls, so seeding from it would
-- launder any escalation already performed straight into the new table and make
-- it permanent. Tested, and it did exactly that.
--
-- So this fails closed. Nurse and admin are re-granted by hand, below, by
-- someone with access to this SQL editor.
insert into public.user_roles (user_id, role)
select id, 'patient' from auth.users
on conflict (user_id) do nothing;

-- ------------------------------------------------- policies: ask the table
-- Same intent as before in every case. Only the source of truth changes.

-- check_ins
drop policy if exists "read own or all-if-nurse" on public.check_ins;
create policy "read own or all-if-nurse" on public.check_ins for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());
drop policy if exists "admin reads check-ins" on public.check_ins;
create policy "admin reads check-ins" on public.check_ins for select to authenticated
  using (public.is_admin());

-- reorders
drop policy if exists "read own or all-if-nurse reorders" on public.reorders;
create policy "read own or all-if-nurse reorders" on public.reorders for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());
drop policy if exists "admin reads reorders" on public.reorders;
create policy "admin reads reorders" on public.reorders for select to authenticated
  using (public.is_admin());

-- messages
drop policy if exists "read own thread or nurse" on public.messages;
create policy "read own thread or nurse" on public.messages for select to authenticated
  using (thread_user = auth.uid() or public.is_nurse());
-- sender_role is supplied by the client and the UI renders 'nurse' as
-- "Care team", so a patient could otherwise post a fabricated clinical message
-- into their own record. It must now match who the database says you are.
drop policy if exists "send to own thread or nurse" on public.messages;
create policy "send to own thread or nurse" on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (thread_user = auth.uid() or public.is_nurse())
    and (sender_role = 'nurse') = public.is_nurse()
  );
drop policy if exists "admin reads messages" on public.messages;
create policy "admin reads messages" on public.messages for select to authenticated
  using (public.is_admin());

-- guide_progress
drop policy if exists "read own progress or nurse" on public.guide_progress;
create policy "read own progress or nurse" on public.guide_progress for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());
drop policy if exists "admin reads guide_progress" on public.guide_progress;
create policy "admin reads guide_progress" on public.guide_progress for select to authenticated
  using (public.is_admin());

-- patient_profile
drop policy if exists "read own or all-if-nurse (profile)" on public.patient_profile;
create policy "read own or all-if-nurse (profile)" on public.patient_profile for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());
drop policy if exists "admin reads patient_profile" on public.patient_profile;
create policy "admin reads patient_profile" on public.patient_profile for select to authenticated
  using (public.is_admin());

-- diary_photos (rows)
drop policy if exists "read own or all-if-nurse (photos)" on public.diary_photos;
create policy "read own or all-if-nurse (photos)" on public.diary_photos for select to authenticated
  using (user_id = auth.uid() or public.is_nurse());
drop policy if exists "admin reads diary_photos" on public.diary_photos;
create policy "admin reads diary_photos" on public.diary_photos for select to authenticated
  using (public.is_admin());

-- diary photos (the files themselves)
drop policy if exists "diary read own or nurse" on storage.objects;
create policy "diary read own or nurse" on storage.objects for select to authenticated
  using (
    bucket_id = 'diary-photos'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_nurse())
  );
drop policy if exists "diary read admin" on storage.objects;
create policy "diary read admin" on storage.objects for select to authenticated
  using (bucket_id = 'diary-photos' and public.is_admin());

-- site_content
drop policy if exists "admin writes content" on public.site_content;
create policy "admin writes content" on public.site_content for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- community_groups
drop policy if exists "admin writes directory" on public.community_groups;
create policy "admin writes directory" on public.community_groups for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------- granting a real role
-- There is no UI for this on purpose. To make someone a nurse or an admin, run
-- this here in the SQL Editor, which requires access to the Supabase project:
--
--   insert into public.user_roles (user_id, role)
--   select id, 'nurse' from auth.users where email = 'someone@example.com'
--   on conflict (user_id) do update set role = excluded.role, assigned_at = now();
