-- Stoma Alert — admin role + reorder supplier breakdown (prototype; test data only)
-- Run this in Supabase → SQL Editor, or let the GitHub integration apply it.
--
-- 1) Capture which supplier a reorder was placed with, so Admin can break demand
--    down by supplier × product. Older rows stay null → shown as "Not specified".
-- 2) Give the 'admin' role (role in user_metadata) read access across patient data,
--    mirroring the existing nurse read policies. Additive: patients still see only
--    their own; nurses unchanged. NOTE: prototype-grade — role is self-selected at
--    signup and NOT yet enforced server-side. Harden before real patients.

-- ---- reorders: supplier column ----
alter table public.reorders add column if not exists supplier text;

-- ---- admin read policies (one per patient table) ----
drop policy if exists "admin reads check-ins" on public.check_ins;
create policy "admin reads check-ins" on public.check_ins for select to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

drop policy if exists "admin reads reorders" on public.reorders;
create policy "admin reads reorders" on public.reorders for select to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

drop policy if exists "admin reads messages" on public.messages;
create policy "admin reads messages" on public.messages for select to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

drop policy if exists "admin reads guide_progress" on public.guide_progress;
create policy "admin reads guide_progress" on public.guide_progress for select to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

drop policy if exists "admin reads patient_profile" on public.patient_profile;
create policy "admin reads patient_profile" on public.patient_profile for select to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

drop policy if exists "admin reads diary_photos" on public.diary_photos;
create policy "admin reads diary_photos" on public.diary_photos for select to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

-- diary photo files live in storage; let admins read the bucket too
drop policy if exists "diary read admin" on storage.objects;
create policy "diary read admin" on storage.objects for select to authenticated
  using (
    bucket_id = 'diary-photos'
    and coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin'
  );
