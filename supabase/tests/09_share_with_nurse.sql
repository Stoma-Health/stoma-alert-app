-- 0021: patient-controlled sharing.
--
-- Two claims are being defended here, and they pull in opposite directions.
-- First, that "Share with nurse" is REAL: before the patient taps it, a nurse
-- sees nothing; after, they see that row and only that row. Second, that the
-- patient keeps the pen: a nurse must never be able to set the flag themselves,
-- or the consent is the clinician's rather than the patient's.
--
-- Suite 08 already proves an unshared note stays invisible. This one proves the
-- other half, and that revoking works — a share you cannot take back is not
-- consent, it is publication.

insert into auth.users (id,email,raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111','alice@example.com','{}'),
  ('33333333-3333-3333-3333-333333333333','nora@example.com','{}');
insert into public.user_roles (user_id,role) select id,'nurse' from auth.users where email='nora@example.com'
  on conflict (user_id) do update set role=excluded.role;

create or replace function pg_temp.t(label text, expected boolean, actual boolean) returns void
language plpgsql as $$ begin
  raise notice '%  %', case when expected=actual then 'PASS' else '*** FAIL ***' end, label;
end $$;

insert into public.diary_notes (user_id,title,body) values
  ('11111111-1111-1111-1111-111111111111','Kept back','Nobody else needs this.'),
  ('11111111-1111-1111-1111-111111111111','Handed over','Ask about the flange.');
insert into public.care_logs (user_id,output_ml,pouch_changed) values
  ('11111111-1111-1111-1111-111111111111', 900, 2),
  ('11111111-1111-1111-1111-111111111111',1800, 5);

select pg_temp.t('nothing is shared until someone shares it', true,
  (select count(*) from public.diary_notes where shared_with_nurse)=0
  and (select count(*) from public.care_logs where shared_with_nurse)=0);

set role authenticated;

-- ---------------------------------------------------- before the patient taps
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('nurse sees no notes before anything is shared', true,
  (select count(*) from public.diary_notes)=0);
select pg_temp.t('nurse sees no care logs before anything is shared', true,
  (select count(*) from public.care_logs)=0);

-- ------------------------------------------------------------- patient shares
select public.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.t('patient still sees everything of her own', true,
  (select count(*) from public.diary_notes)=2 and (select count(*) from public.care_logs)=2);
update public.diary_notes set shared_with_nurse=true where title='Handed over';
update public.care_logs   set shared_with_nurse=true where output_ml=1800;

-- --------------------------------------------------------------- what a nurse
-- gets is exactly the shared row, and nothing either side of it.
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('nurse sees the shared note', true,
  (select count(*) from public.diary_notes)=1);
select pg_temp.t('and it is the one the patient chose', true,
  (select title from public.diary_notes)='Handed over');
select pg_temp.t('the withheld note stays invisible', true,
  (select count(*) from public.diary_notes where title='Kept back')=0);
select pg_temp.t('nurse sees the shared care log', true,
  (select count(*) from public.care_logs)=1 and (select output_ml from public.care_logs)=1800);

-- The pen stays with the patient.
do $$ declare n int; begin
  update public.diary_notes set shared_with_nurse=false;
  get diagnostics n = row_count;
  perform pg_temp.t('a nurse cannot unshare what was shared with them', true, n=0);
end $$;
do $$ declare n int; begin
  update public.care_logs set shared_with_nurse=true;
  get diagnostics n = row_count;
  perform pg_temp.t('a nurse cannot share a log the patient held back', true, n=0);
end $$;
select pg_temp.t('so the nurse still sees exactly one care log', true,
  (select count(*) from public.care_logs)=1);

-- ------------------------------------------------------------ taking it back
select public.act_as('11111111-1111-1111-1111-111111111111');
update public.diary_notes set shared_with_nurse=false where title='Handed over';
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('unsharing a note takes it away again', true,
  (select count(*) from public.diary_notes)=0);

reset role;
select pg_temp.t('and the patient keeps both notes throughout', true,
  (select count(*) from public.diary_notes)=2);
