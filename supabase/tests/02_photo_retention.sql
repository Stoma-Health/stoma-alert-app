insert into auth.users (id,email,raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111','alice@example.com','{}'),
  ('22222222-2222-2222-2222-222222222222','mallory@example.com','{}'),
  ('33333333-3333-3333-3333-333333333333','nora@example.com','{}');
insert into public.user_roles (user_id,role) select id,'admin' from auth.users where email='nora@example.com'
  on conflict (user_id) do update set role=excluded.role;

-- Alice: one recent photo, one 13 months old, one 13 months old but pinned.
insert into public.diary_photos (user_id,path,created_at,keep) values
  ('11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111/new.jpg', now(), false),
  ('11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111/old.jpg', now() - interval '13 months', false),
  ('11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111/kept.jpg',now() - interval '13 months', true);

create or replace function pg_temp.t(label text, expected boolean, actual boolean) returns void
language plpgsql as $$ begin
  raise notice '%  %', case when expected=actual then 'PASS' else '*** FAIL ***' end, label;
end $$;

select pg_temp.t('default retention is 12 months', true, public.photo_retention_months()=12);

set role authenticated;
select public.act_as('33333333-3333-3333-3333-333333333333');   -- admin
select pg_temp.t('admin sees exactly 1 expired photo', true, (select count(*) from public.expired_photos())=1);
select pg_temp.t('the expired one is old.jpg', true,
  (select path like '%old.jpg' from public.expired_photos()));
select pg_temp.t('pinned photo is NOT expired', true,
  (select count(*) from public.expired_photos() where path like '%kept.jpg')=0);
select pg_temp.t('recent photo is NOT expired', true,
  (select count(*) from public.expired_photos() where path like '%new.jpg')=0);

select public.act_as('22222222-2222-2222-2222-222222222222');   -- an ordinary patient
select pg_temp.t('patient cannot enumerate others'' file paths', true,
  (select count(*) from public.expired_photos())=0);
do $$ declare ok boolean := false; begin
  begin update public.app_settings set value='1'::jsonb where key='photo_retention_months';
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('patient cannot shorten retention to destroy evidence', true, ok);
end $$;

select public.act_as('11111111-1111-1111-1111-111111111111');   -- Alice
select pg_temp.t('patient sees expiry dates on her own photos', true,
  (select count(*) from public.diary_photos_with_expiry)=3);
select pg_temp.t('her old photo is flagged expired to her', true,
  (select is_expired from public.diary_photos_with_expiry where path like '%old.jpg'));
select pg_temp.t('she is warned about photos ageing out', true,
  public.my_photos_expiring_within(30)=1);
do $$ declare ok boolean := true; begin
  begin update public.diary_photos set keep=true where path like '%old.jpg';
  exception when others then ok := false; end;
  perform pg_temp.t('patient CAN pin a photo to keep it', true, ok);
end $$;
select pg_temp.t('pinning removed it from the purge list', true,
  public.my_photos_expiring_within(30)=0);

-- Changing the rule must move every expiry, not just new photos.
reset role;
update public.app_settings set value='24'::jsonb where key='photo_retention_months';
set role authenticated;
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('raising retention to 24m empties the purge list', true,
  (select count(*) from public.expired_photos())=0);
reset role;
update public.app_settings set value='6'::jsonb where key='photo_retention_months';
set role authenticated;
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('lowering it to 6m still respects the pin', true,
  (select count(*) from public.expired_photos() where path like '%kept.jpg')=0);
