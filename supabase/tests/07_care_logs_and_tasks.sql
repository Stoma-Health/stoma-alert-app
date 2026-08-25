-- 0018: care logs and care plan tasks.
--
-- The asymmetry is the point and is what these assertions defend. A nurse may
-- SET a task, because that is what a care plan is; a nurse may not EDIT a
-- patient's own record of what happened to them, because an altered account
-- with no author is worse than no account. Neither may a nurse delete a task
-- they set, or the plan becomes unauditable.

insert into auth.users (id,email,raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111','alice@example.com','{}'),
  ('22222222-2222-2222-2222-222222222222','mallory@example.com','{}'),
  ('33333333-3333-3333-3333-333333333333','nora@example.com','{}');
insert into public.user_roles (user_id,role) select id,'nurse' from auth.users where email='nora@example.com'
  on conflict (user_id) do update set role=excluded.role;

create or replace function pg_temp.t(label text, expected boolean, actual boolean) returns void
language plpgsql as $$ begin
  raise notice '%  %', case when expected=actual then 'PASS' else '*** FAIL ***' end, label;
end $$;

insert into public.care_logs (user_id,output_ml,hydration_ml,consistency,pain,leak,pouch_changed) values
  ('11111111-1111-1111-1111-111111111111', 700,2000,'Porridge',1,false,1),
  ('11111111-1111-1111-1111-111111111111',1800,1200,'Liquid',  4,true, 3);
insert into public.care_tasks (user_id,title,due_date,completed) values
  ('11111111-1111-1111-1111-111111111111','Measure your stoma', current_date + 2, false);

-- Constraints, so a typo cannot become a clinical figure.
do $$ declare ok boolean := false; begin
  begin insert into public.care_logs (user_id,output_ml) values
    ('11111111-1111-1111-1111-111111111111', 99999);
  exception when check_violation then ok := true; end;
  perform pg_temp.t('an implausible output is rejected, not stored', true, ok);
end $$;
do $$ declare ok boolean := false; begin
  begin insert into public.care_logs (user_id,pain) values
    ('11111111-1111-1111-1111-111111111111', 11);
  exception when check_violation then ok := true; end;
  perform pg_temp.t('pain stays on its 0-10 scale', true, ok);
end $$;
do $$ declare ok boolean := false; begin
  begin insert into public.care_logs (user_id,consistency) values
    ('11111111-1111-1111-1111-111111111111', 'Runny');
  exception when check_violation then ok := true; end;
  perform pg_temp.t('consistency is a fixed vocabulary', true, ok);
end $$;

select pg_temp.t('the high-output day is findable', true,
  (select count(*) from public.care_logs where output_ml >= 1500)=1);

set role authenticated;

-- ---------------------------------------------------------------- the patient
select public.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.t('patient sees her own care logs', true,
  (select count(*) from public.care_logs)=2);
do $$ declare n int; begin
  update public.care_logs set food='toast' where output_ml=700;
  get diagnostics n = row_count;
  perform pg_temp.t('patient can correct her own entry', true, n=1);
end $$;
do $$ declare n int; begin
  update public.care_tasks set completed=true;
  get diagnostics n = row_count;
  perform pg_temp.t('patient can tick off a task', true, n=1);
end $$;

-- ------------------------------------------------------------- another patient
select public.act_as('22222222-2222-2222-2222-222222222222');
select pg_temp.t('patient cannot read another patient''s care logs', true,
  (select count(*) from public.care_logs)=0);
select pg_temp.t('patient cannot read another patient''s tasks', true,
  (select count(*) from public.care_tasks)=0);
do $$ declare ok boolean := false; begin
  begin insert into public.care_logs (user_id,output_ml) values
    ('11111111-1111-1111-1111-111111111111', 4000);
  exception when others then ok := true; end;
  perform pg_temp.t('patient cannot write into another patient''s record', true, ok);
end $$;

-- --------------------------------------------------------------------- nurse
-- Changed by 0021. A nurse used to read every care log; now they read only what
-- the patient shared. The two assertions below used to expect 2 and 1; they
-- expect 0 until something is shared, and the sharing behaviour itself is
-- proved in suite 09.
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('nurse reads no care log until one is shared', true,
  (select count(*) from public.care_logs)=0);
select pg_temp.t('the leak and high output stay unshared', true,
  (select count(*) from public.care_logs where leak is true and output_ml>=1500)=0);
do $$ declare ok boolean := false; begin
  begin update public.care_logs set output_ml=100 where output_ml=1800;
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('nurse CANNOT rewrite a patient''s own account', true, ok);
end $$;
do $$ declare ok boolean := false; begin
  begin delete from public.care_logs;
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('nurse cannot delete a care log', true, ok);
end $$;
do $$ declare n int; begin
  insert into public.care_tasks (user_id,title,due_date)
    values ('11111111-1111-1111-1111-111111111111','Bloods at the surgery',current_date+7);
  get diagnostics n = row_count;
  perform pg_temp.t('nurse CAN set a task — that is what a care plan is', true, n=1);
end $$;
do $$ declare ok boolean := false; begin
  begin delete from public.care_tasks where title='Bloods at the surgery';
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('nurse cannot delete a task once set', true, ok);
end $$;
