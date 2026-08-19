-- Minimal stand-in for the parts of Supabase the migrations touch, so the real
-- migration files run unmodified and RLS behaves as it does in production.
-- Roles are cluster-wide, not per-database, so these must be idempotent: each
-- suite gets its own database on the same cluster.
do $$ begin
  create role anon nologin;
exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role nologin bypassrls;
exception when duplicate_object then null; end $$;

create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb default '{}'::jsonb
);

-- The current request's identity, set per-test via set_config.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

-- Supabase puts user_metadata straight into the JWT. That is the whole problem:
-- the user can edit it, so anything trusting it is trusting the attacker.
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  owner uuid
);
alter table storage.objects enable row level security;

create or replace function storage.foldername(name text) returns text[]
  language sql immutable as $$ select string_to_array(name, '/') $$;

grant usage on schema auth, storage, public to anon, authenticated, service_role;
grant all on all tables in schema storage to authenticated;
grant all on all tables in schema auth to authenticated;

-- Become a given user for the duration of a test.
create or replace function public.act_as(p_id uuid) returns void language plpgsql as $$
declare meta jsonb;
begin
  select raw_user_meta_data into meta from auth.users where id = p_id;
  perform set_config('request.jwt.claim.sub', p_id::text, false);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_id::text, 'user_metadata', coalesce(meta,'{}'::jsonb))::text, false);
end $$;

-- Gaps found by running the real migrations: they expect a realtime publication
-- and a storage.buckets table to exist.
create publication supabase_realtime;
create table storage.buckets (id text primary key, name text, public boolean);
grant all on all tables in schema storage to authenticated;
