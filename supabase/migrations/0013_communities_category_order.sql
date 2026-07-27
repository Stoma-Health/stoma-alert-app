-- Stoma Alert — explicit category ordering for the community directory
-- Run this in Supabase → SQL Editor AFTER 0012.
--
-- Categories were ordered alphabetically, which is arbitrary. cat_sort lets an
-- admin decide what a patient sees first. Lower sorts first, ties fall back to
-- the category name.
--
-- Also moves the WhatsApp group out of General into its own category at the top:
-- it's the quickest route to a human, so it shouldn't be buried under Facebook groups.

alter table public.community_groups
  add column if not exists cat_sort int not null default 100;

comment on column public.community_groups.cat_sort is
  'Order of this row''s CATEGORY in the picker (low first). Keep it the same for every row sharing a category.';

-- WhatsApp first
update public.community_groups
   set category = 'Chat & quick support', cat_sort = 10
 where platform = 'whatsapp';

-- then the rest, most-specific first
update public.community_groups set cat_sort = 20 where category = 'By stoma type';
update public.community_groups set cat_sort = 30 where category = 'Getting started';
update public.community_groups set cat_sort = 40 where category = 'Region';
update public.community_groups set cat_sort = 50 where category = 'General';
update public.community_groups set cat_sort = 60 where category = 'Products & practical';
update public.community_groups set cat_sort = 70 where category = 'Family & carers';
update public.community_groups set cat_sort = 80 where category = 'Dating & relationships';

-- To reorder later, just change the number, e.g.:
--   update public.community_groups set cat_sort = 15 where category = 'Region';
