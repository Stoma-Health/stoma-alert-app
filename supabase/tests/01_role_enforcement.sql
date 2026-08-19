insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111','alice@example.com','{"role":"patient"}'),
  ('22222222-2222-2222-2222-222222222222','mallory@example.com','{"role":"patient"}'),
  ('33333333-3333-3333-3333-333333333333','nora@example.com','{"role":"patient"}');
insert into public.check_ins (user_id,patient_name,skin,note) values
  ('11111111-1111-1111-1111-111111111111','Alice',2,'sore and weeping');
insert into public.diary_photos (user_id,patient_name,path) values
  ('11111111-1111-1111-1111-111111111111','Alice','11111111-1111-1111-1111-111111111111/s.jpg');
insert into public.patient_profile (user_id) values ('11111111-1111-1111-1111-111111111111');
insert into public.user_roles (user_id,role) select id,'nurse' from auth.users where email='nora@example.com'
  on conflict (user_id) do update set role=excluded.role;
update auth.users set raw_user_meta_data='{"role":"admin"}' where email='mallory@example.com';

create or replace function pg_temp.t(label text, expected boolean, actual boolean) returns void
language plpgsql as $$ begin
  raise notice '%  %', case when expected=actual then 'PASS' else '*** FAIL ***' end, label;
end $$;

set role authenticated;
select public.act_as('22222222-2222-2222-2222-222222222222');
select pg_temp.t('attacker with role:admin in metadata is a patient to the DB', true, public.app_role()='patient');
select pg_temp.t('attacker reads no check-ins',   true, (select count(*) from public.check_ins)=0);
select pg_temp.t('attacker reads no photos',      true, (select count(*) from public.diary_photos)=0);
select pg_temp.t('attacker reads no profiles',    true, (select count(*) from public.patient_profile)=0);
select pg_temp.t('attacker reads no messages',    true, (select count(*) from public.messages)=0);
select pg_temp.t('attacker sees only own role row', true, (select count(*) from public.user_roles)<=1);

do $$ declare ok boolean := false; begin
  begin insert into public.user_roles(user_id,role) values(auth.uid(),'admin')
        on conflict (user_id) do update set role='admin';
  exception when others then ok := true; end;
  perform pg_temp.t('attacker cannot promote itself', true, ok);
end $$;

do $$ declare ok boolean := false; begin
  begin insert into public.site_content(key,value) values('x','"x"'::jsonb);
  exception when others then ok := true; end;
  perform pg_temp.t('attacker cannot write site content', true, ok);
end $$;

select public.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.t('patient still sees own check-in', true, (select count(*) from public.check_ins)=1);
select pg_temp.t('patient still sees own photo',    true, (select count(*) from public.diary_photos)=1);
do $$ declare ok boolean := false; begin
  begin insert into public.messages(thread_user,sender_id,sender_role,body)
        values(auth.uid(),auth.uid(),'nurse','your stoma looks fine');
  exception when others then ok := true; end;
  perform pg_temp.t('patient cannot forge a "Care team" message', true, ok);
end $$;
do $$ declare ok boolean := true; begin
  begin insert into public.messages(thread_user,sender_id,sender_role,body)
        values(auth.uid(),auth.uid(),'patient','is this infected?');
  exception when others then ok := false; end;
  perform pg_temp.t('patient CAN send a normal message', true, ok);
end $$;

select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('real nurse sees the caseload',   true, (select count(*) from public.check_ins)=1);
select pg_temp.t('real nurse sees photos',         true, (select count(*) from public.diary_photos)=1);
select pg_temp.t('real nurse sees the thread',     true, (select count(*) from public.messages)=1);
do $$ declare ok boolean := false; begin
  begin insert into public.site_content(key,value) values('y','"y"'::jsonb);
  exception when others then ok := true; end;
  perform pg_temp.t('nurse is not an admin', true, ok);
end $$;
do $$ declare ok boolean := true; begin
  begin insert into public.messages(thread_user,sender_id,sender_role,body)
        values('11111111-1111-1111-1111-111111111111',auth.uid(),'nurse','ring the ward');
  exception when others then ok := false; end;
  perform pg_temp.t('nurse CAN reply as Care team', true, ok);
end $$;

reset role;
insert into public.user_roles(user_id,role) select id,'admin' from auth.users where email='nora@example.com'
  on conflict (user_id) do update set role='admin';
set role authenticated;
select public.act_as('33333333-3333-3333-3333-333333333333');
do $$ declare ok boolean := true; begin
  begin insert into public.site_content(key,value) values('z','"z"'::jsonb);
  exception when others then ok := false; end;
  perform pg_temp.t('real admin CAN write content', true, ok);
end $$;

reset role;
insert into auth.users(id,email,raw_user_meta_data)
  values('44444444-4444-4444-4444-444444444444','chancer@example.com','{"role":"admin"}');
set role authenticated;
select public.act_as('44444444-4444-4444-4444-444444444444');
select pg_temp.t('new signup asking for admin gets patient', true, public.app_role()='patient');
select pg_temp.t('new signup sees nobody else''s data', true, (select count(*) from public.check_ins)=0);
