-- Stoma Alert — community directory: "browse" rows + patient-added groups
-- Run this in Supabase → SQL Editor AFTER 0011_communities.sql.
--
-- Solves the chicken-and-egg problem: you can't list group URLs you don't have,
-- and you can't get the URLs without joining the groups.
--
-- Two additions:
--   1) kind = 'browse'  — the row is a Facebook group SEARCH, not one group.
--      Opens Facebook's own group search so the patient sees live results and
--      joins whichever suits them. No URL for us to source, and it never goes stale.
--   2) patient-added groups — once someone HAS joined, they have the URL. They
--      paste it and it becomes their own entry. Over time this shows which groups
--      real patients use, and the popular ones can be promoted into the directory.

-- ---- 1) browse rows ----
alter table public.community_groups
  add column if not exists kind text not null default 'group';

alter table public.community_groups drop constraint if exists community_groups_kind_chk;
alter table public.community_groups add constraint community_groups_kind_chk
  check (kind in ('group','browse'));

comment on column public.community_groups.kind is
  '''group'' = a single joinable group (tickable). ''browse'' = a search/discovery link (opens, not tickable).';

-- ---- 2) patient-added entries ----
-- Patients must never write to the shared directory, so their own groups live
-- in user_communities with group_id null and custom_name/custom_url set.
alter table public.user_communities add column if not exists id uuid default gen_random_uuid();
update public.user_communities set id = gen_random_uuid() where id is null;
alter table public.user_communities alter column id set not null;

alter table public.user_communities drop constraint if exists user_communities_pkey;
alter table public.user_communities add primary key (id);

alter table public.user_communities alter column group_id drop not null;
alter table public.user_communities add column if not exists custom_name text;
alter table public.user_communities add column if not exists custom_url  text;
alter table public.user_communities add column if not exists platform    text;

-- a patient can only tick a given directory group once
create unique index if not exists user_communities_user_group_uidx
  on public.user_communities (user_id, group_id) where group_id is not null;

-- every row is EITHER a directory group OR a patient-added one, never both
alter table public.user_communities drop constraint if exists user_communities_source_chk;
alter table public.user_communities add constraint user_communities_source_chk check (
  (group_id is not null and custom_url is null and custom_name is null)
  or
  (group_id is null and custom_url is not null and custom_name is not null)
);

-- only http/https links, so a stored URL can never be javascript: or data:
alter table public.user_communities drop constraint if exists user_communities_url_chk;
alter table public.user_communities add constraint user_communities_url_chk
  check (custom_url is null or custom_url ~* '^https?://');

-- patients may rename their own entries
drop policy if exists "update own communities" on public.user_communities;
create policy "update own communities" on public.user_communities for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---- seed: discovery rows, so Community is useful with zero sourced URLs ----
-- These open Facebook's group search. Safe to edit the q= terms later.
insert into public.community_groups (name, url, platform, category, description, kind, sort)
select v.name, v.url, 'facebook', v.category, v.description, 'browse', v.sort
from (values
  ('Ileostomy groups',   'https://www.facebook.com/search/groups/?q=ileostomy',            'By stoma type',   'Browse ileostomy groups on Facebook',        110),
  ('Colostomy groups',   'https://www.facebook.com/search/groups/?q=colostomy',            'By stoma type',   'Browse colostomy groups on Facebook',        120),
  ('Urostomy groups',    'https://www.facebook.com/search/groups/?q=urostomy',             'By stoma type',   'Browse urostomy groups on Facebook',         130),
  ('New to a stoma',     'https://www.facebook.com/search/groups/?q=new%20ostomy',         'Getting started', 'Groups for the first weeks after surgery',   210),
  ('UK ostomy groups',   'https://www.facebook.com/search/groups/?q=ostomy%20uk',          'Region',          'UK-based groups and NHS know-how',           310),
  ('Parents and carers', 'https://www.facebook.com/search/groups/?q=ostomy%20carers',      'Family & carers', 'For family looking after someone',           410)
) as v(name, url, category, description, sort)
where not exists (
  select 1 from public.community_groups g where g.url = v.url
);
