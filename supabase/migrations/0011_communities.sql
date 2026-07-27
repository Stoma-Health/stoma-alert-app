-- Stoma Alert — community directory + per-patient memberships (prototype; test data only)
-- Run this in Supabase → SQL Editor, or let the GitHub integration apply it.
--
-- Replaces the two hard-coded Facebook/WhatsApp links on Home with a directory
-- an admin curates from the database. Adding a group is a row, not a redeploy.
--
-- Two tables:
--   community_groups  — the directory. Admin writes, any signed-in user reads.
--   user_communities  — which groups THIS patient says they're part of.
--
-- Facebook note: Meta deprecated user_groups, user_managed_groups and the whole
-- Groups API, so an app CANNOT read a person's real group memberships. This is a
-- self-declared list: the patient ticks what they're in. No Facebook login needed.

-- ---- the directory ----
create table if not exists public.community_groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  url         text not null,
  platform    text not null default 'facebook',   -- facebook | whatsapp | web
  category    text not null default 'General',    -- grouping shown in the picker
  description text,
  sort        int  not null default 100,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists community_groups_active_idx
  on public.community_groups (active, category, sort);

alter table public.community_groups enable row level security;

-- anyone signed in can browse the directory
drop policy if exists "read directory" on public.community_groups;
create policy "read directory" on public.community_groups for select to authenticated
  using (active);

-- only admins curate it (mirrors site_content in 0010)
drop policy if exists "admin writes directory" on public.community_groups;
create policy "admin writes directory" on public.community_groups for all to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin')
  with check (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');

-- ---- which groups a patient is part of ----
-- Deliberately NOT readable by nurse or admin. Which support groups someone
-- belongs to is health-adjacent personal data and nothing in the clinical flow
-- needs it. If a caseload view ever needs it, add the policy consciously and
-- cover it in the privacy notice first.
create table if not exists public.user_communities (
  user_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  group_id  uuid not null references public.community_groups(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

alter table public.user_communities enable row level security;

drop policy if exists "read own communities" on public.user_communities;
create policy "read own communities" on public.user_communities for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "join own communities" on public.user_communities;
create policy "join own communities" on public.user_communities for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "leave own communities" on public.user_communities;
create policy "leave own communities" on public.user_communities for delete to authenticated
  using (user_id = auth.uid());

-- ---- seed: the two groups that were previously hard-coded in index.html ----
-- Only real, already-in-use links are seeded. Add the rest from the Supabase
-- table editor (or the Admin → Content screen once it covers this table).
insert into public.community_groups (name, url, platform, category, description, sort)
select 'Stoma Alert community',
       'https://www.facebook.com/groups/501488602109177',
       'facebook', 'General',
       'Support & tips from others on the same journey', 10
where not exists (
  select 1 from public.community_groups
  where url = 'https://www.facebook.com/groups/501488602109177'
);

insert into public.community_groups (name, url, platform, category, description, sort)
select 'Stoma Alert WhatsApp group',
       'https://chat.whatsapp.com/J0S5cmprFsHFhfrVgeEl1W',
       'whatsapp', 'General',
       'Chat & quick support in the group', 20
where not exists (
  select 1 from public.community_groups
  where url = 'https://chat.whatsapp.com/J0S5cmprFsHFhfrVgeEl1W'
);
