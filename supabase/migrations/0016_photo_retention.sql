-- Stoma Alert — photo retention
--
-- Stoma photos are special-category health data. Keeping them forever is both a
-- storage bill and a GDPR problem: Art. 5(1)(e) says personal data is kept no
-- longer than necessary, and a retention schedule has to be documented AND
-- technically enforced, not just written down.
--
-- This migration defines the rule and makes it queryable. It DELETES NOTHING.
-- Deleting the row here would not reclaim the file anyway: the image lives in
-- Supabase Storage, which is only reachable through the storage API with the
-- service-role key. The purge runner is a separate, deliberate step.
--
-- The default is 12 months, with a patient able to mark individual photos as
-- kept. A blunt sweep was considered and rejected: the photograph that matters
-- most clinically is often the oldest one, because that is what shows a hernia
-- or a retraction developing slowly. Data minimisation and clinical usefulness
-- both get a say, and the patient decides the exceptions.
--
-- Run in Supabase → SQL Editor. Safe to re-run.

-- --------------------------------------------------------------- the setting
-- A table rather than a constant, so the retention period is a documented,
-- dated, auditable value that can be changed without a code deploy.
create table if not exists public.app_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;

-- Everyone signed in may read it: the app tells patients when their photos
-- expire, and it can hardly do that from a secret.
drop policy if exists "read settings" on public.app_settings;
create policy "read settings" on public.app_settings for select to authenticated
  using (true);

drop policy if exists "admin writes settings" on public.app_settings;
create policy "admin writes settings" on public.app_settings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

insert into public.app_settings (key, value)
values ('photo_retention_months', '12'::jsonb)
on conflict (key) do nothing;

create or replace function public.photo_retention_months() returns integer
  language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select (value #>> '{}')::int from public.app_settings
                   where key = 'photo_retention_months'), 12)
$$;
grant execute on function public.photo_retention_months() to authenticated;

-- ------------------------------------------------------------ the exemption
-- A patient may mark a photo as kept, and it is then never swept. Their choice,
-- their record. The existing "update own diary photos" policy already limits
-- this to the owner's own rows.
alter table public.diary_photos add column if not exists keep boolean not null default false;

-- ------------------------------------------------------------- what expires
-- A view rather than a stored column: the retention period can change, and a
-- stored expiry would quietly disagree with the setting the moment it did.
create or replace view public.diary_photos_with_expiry
with (security_invoker = true) as
select p.*,
       p.created_at + make_interval(months => public.photo_retention_months()) as expires_at,
       (not p.keep
        and p.created_at + make_interval(months => public.photo_retention_months()) <= now())
         as is_expired
from public.diary_photos p;

grant select on public.diary_photos_with_expiry to authenticated;

-- --------------------------------------------------------- the purge listing
-- What a purge WOULD remove. Deliberately a listing, not a delete: the caller
-- (a scheduled job holding the service-role key) removes the storage objects
-- first, then the rows, because a row deleted before its file leaves an orphan
-- nobody will ever find again.
--
-- Admin-only, so a curious patient cannot enumerate other people's file paths.
create or replace function public.expired_photos()
  returns table (id uuid, user_id uuid, path text, created_at timestamptz)
  language sql stable security definer set search_path = public, pg_temp as $$
  select p.id, p.user_id, p.path, p.created_at
  from public.diary_photos p
  where not p.keep
    and p.created_at + make_interval(months => public.photo_retention_months()) <= now()
    and public.is_admin()
  order by p.created_at
$$;
grant execute on function public.expired_photos() to authenticated;

-- A count anyone may see for their OWN photos, so the app can warn a patient
-- that something is about to age out while they can still choose to keep it.
create or replace function public.my_photos_expiring_within(p_days integer default 30)
  returns integer
  language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from public.diary_photos p
  where p.user_id = auth.uid()
    and not p.keep
    and p.created_at + make_interval(months => public.photo_retention_months())
        <= now() + make_interval(days => p_days)
$$;
grant execute on function public.my_photos_expiring_within(integer) to authenticated;

-- --------------------------------------------------------- changing the rule
--   update public.app_settings set value = '24'::jsonb, updated_at = now()
--    where key = 'photo_retention_months';
