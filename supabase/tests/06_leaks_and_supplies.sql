-- 0017: leak tracking + supply reorder thresholds.
--
-- Two things worth proving rather than assuming. First that a patient's supply
-- cupboard is genuinely private and that a nurse can read it but not rewrite
-- it, because "nurse edits the count" would put a number in the record that
-- nobody actually looked at. Second that a NULL leak stays NULL: if a
-- pre-2026-08 check-in ever starts counting as "no leak", every leak statistic
-- we produce afterwards is quietly wrong in the safe-sounding direction.

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

-- Alice's history: one check-in from before the question existed, one where she
-- was asked and said no, one leak.
insert into public.check_ins (user_id,output,skin,comfort,mood,leak,created_at) values
  ('11111111-1111-1111-1111-111111111111',3,3,3,3,null, now() - interval '40 days'),
  ('11111111-1111-1111-1111-111111111111',3,4,4,4,false,now() - interval '2 days'),
  ('11111111-1111-1111-1111-111111111111',2,2,2,3,true, now() - interval '1 day');

select pg_temp.t('null leak is not counted as a leak', true,
  (select count(*) from public.check_ins where leak is true)=1);
select pg_temp.t('null leak is not counted as no-leak either', true,
  (select count(*) from public.check_ins where leak is false)=1);
select pg_temp.t('the untouched historic row stayed null', true,
  (select count(*) from public.check_ins where leak is null)=1);

-- Alice's cupboard, on the 0020 model: a reminder in the future, one landing
-- today, one already past, and one with no reminder at all.
insert into public.supply_items (user_id,name,remind_on,unit) values
  ('11111111-1111-1111-1111-111111111111','Drainable pouch 60mm', current_date + 30,'box'),
  ('11111111-1111-1111-1111-111111111111','Barrier rings',        current_date,     'pack'),
  ('11111111-1111-1111-1111-111111111111','Adhesive remover',     current_date - 4, 'spray'),
  ('11111111-1111-1111-1111-111111111111','Disposal bags',        null,             'roll');
insert into public.supply_items (user_id,name,remind_on) values
  ('22222222-2222-2222-2222-222222222222','Mallory pouches', current_date - 1);

set role authenticated;

-- ---------------------------------------------------------------- the patient
select public.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.t('patient sees only her own 4 items', true,
  (select count(*) from public.supply_items)=4);
select pg_temp.t('a reminder falling today is due (<=, not <)', true,
  (select count(*) from public.supply_items_low where name='Barrier rings')=1);
select pg_temp.t('a reminder already past is due', true,
  (select count(*) from public.supply_items_low where name='Adhesive remover')=1);
select pg_temp.t('a reminder in the future is not due', true,
  (select count(*) from public.supply_items_low where name like 'Drainable%')=0);
-- The one that stops the home badge crying wolf: no reminder is not overdue.
select pg_temp.t('an item with NO reminder is never due', true,
  (select count(*) from public.supply_items_low where name='Disposal bags')=0);
select pg_temp.t('days_overdue counts the days, not the date', true,
  (select days_overdue from public.supply_items_low where name='Adhesive remover')=4);
select pg_temp.t('a reminder landing today is 0 days overdue, not null', true,
  (select days_overdue from public.supply_items_low where name='Barrier rings')=0);
select pg_temp.t('due view does not leak other patients', true,
  (select count(*) from public.supply_items_low where name like 'Mallory%')=0);

-- updated_at must move on its own, or a stale count looks freshly checked.
do $$ declare before timestamptz; after timestamptz; begin
  select updated_at into before from public.supply_items where name='Barrier rings';
  perform pg_sleep(0.05);
  update public.supply_items set remind_on = current_date + 7 where name='Barrier rings';
  select updated_at into after from public.supply_items where name='Barrier rings';
  perform pg_temp.t('updated_at is bumped by the trigger', true, after > before);
end $$;

-- ------------------------------------------------------------- another patient
select public.act_as('22222222-2222-2222-2222-222222222222');
select pg_temp.t('patient cannot see another patient''s cupboard', true,
  (select count(*) from public.supply_items where name like 'Drainable%')=0);
do $$ declare ok boolean := false; begin
  begin update public.supply_items set quantity=0 where name='Barrier rings';
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('patient cannot edit another patient''s cupboard', true, ok);
end $$;
do $$ declare ok boolean := false; begin
  begin insert into public.supply_items (user_id,name) values
    ('11111111-1111-1111-1111-111111111111','planted by mallory');
  exception when others then ok := true; end;
  perform pg_temp.t('patient cannot plant an item in someone else''s list', true, ok);
end $$;

-- --------------------------------------------------------------------- nurse
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('nurse reads across patients', true,
  (select count(*) from public.supply_items)=5);
select pg_temp.t('nurse sees the leak', true,
  (select count(*) from public.check_ins where leak is true)=1);
do $$ declare ok boolean := false; begin
  begin update public.supply_items set quantity=99 where name='Barrier rings';
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('nurse can read a cupboard but NOT rewrite it', true, ok);
end $$;
do $$ declare ok boolean := false; begin
  begin delete from public.supply_items where name='Barrier rings';
    if not found then ok := true; end if;
  exception when others then ok := true; end;
  perform pg_temp.t('nurse cannot delete a patient''s item', true, ok);
end $$;

reset role;
-- Constraints, not conventions: a negative cupboard is a bug, not a state.
do $$ declare ok boolean := false; begin
  begin insert into public.supply_items (user_id,name,quantity) values
    ('11111111-1111-1111-1111-111111111111','negative',-1);
  exception when check_violation then ok := true; end;
  perform pg_temp.t('quantity cannot go negative', true, ok);
end $$;
