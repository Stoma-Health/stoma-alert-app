-- Stoma Alert — editable site content for the Admin Content editor (prototype)
-- Run this in Supabase → SQL Editor, or let the GitHub integration apply it.
--
-- Key/value store: one row per content block (copy, suppliers, products,
-- reorderItem, faq, guides). Everyone signed in can READ (so patients see the
-- edits); only the 'admin' role can WRITE. Prototype-grade — role is self-selected
-- at signup and not yet enforced server-side.

create table if not exists public.site_content (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.site_content enable row level security;

-- anyone signed in can read the content
drop policy if exists "read content" on public.site_content;
create policy "read content" on public.site_content for select to authenticated
  using (true);

-- only admins can create/update/delete content
drop policy if exists "admin writes content" on public.site_content;
create policy "admin writes content" on public.site_content for all to authenticated
  using (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin')
  with check (coalesce(auth.jwt() -> 'user_metadata' ->> 'role','') = 'admin');
