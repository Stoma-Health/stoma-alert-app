-- Stoma Alert — Capture: stoma photo diary (Tier 1) with a private Storage bucket.
-- Photos live in Storage under <user_id>/<file>.jpg; one row per photo in diary_photos
-- with client-computed quality metrics (sharpness / brightness / glare). Run in SQL Editor.

-- 1) private bucket
insert into storage.buckets (id, name, public)
values ('diary-photos', 'diary-photos', false)
on conflict (id) do nothing;

-- 2) metadata table
create table if not exists public.diary_photos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  patient_name  text,
  patient_email text,
  path          text not null,
  quality       jsonb,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists diary_photos_user_created_idx on public.diary_photos (user_id, created_at desc);
create index if not exists diary_photos_email_idx        on public.diary_photos (patient_email, created_at desc);
alter table public.diary_photos enable row level security;

drop policy if exists "insert own diary photos" on public.diary_photos;
create policy "insert own diary photos" on public.diary_photos for insert
  to authenticated with check (user_id = auth.uid());

drop policy if exists "read own or all-if-nurse (photos)" on public.diary_photos;
create policy "read own or all-if-nurse (photos)" on public.diary_photos for select
  to authenticated using (
    user_id = auth.uid()
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse'
  );

-- 3) Storage object policies for the bucket (path prefix = uploader's user id)
drop policy if exists "diary upload own" on storage.objects;
create policy "diary upload own" on storage.objects for insert
  to authenticated with check (
    bucket_id = 'diary-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "diary read own or nurse" on storage.objects;
create policy "diary read own or nurse" on storage.objects for select
  to authenticated using (
    bucket_id = 'diary-photos'
    and ( (storage.foldername(name))[1] = auth.uid()::text
          or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') = 'nurse' )
  );
