-- 0019: private diary notes.
--
-- The whole point of this suite is the ABSENCE of a nurse policy. Every other
-- patient table in this schema lets a nurse read; diary_notes must not, because
-- the button in the app says "private". If someone later adds a nurse read
-- policy for convenience, the assertion below is what stops the word "private"
-- quietly becoming false.

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

insert into public.diary_notes (user_id,title,body) values
  ('11111111-1111-1111-1111-111111111111','Curry','Regretted it by ten.'),
  ('11111111-1111-1111-1111-111111111111', null, 'Ask about flange size on Tuesday.');

select pg_temp.t('a note can be saved without a title', true,
  (select count(*) from public.diary_notes where title is null)=1);

do $$ declare ok boolean := false; begin
  begin insert into public.diary_notes (user_id,title) values
    ('11111111-1111-1111-1111-111111111111','A heading and nothing else');
  exception when not_null_violation then ok := true; end;
  perform pg_temp.t('a note with no body is rejected', true, ok);
end $$;

set role authenticated;

-- ---------------------------------------------------------------- the patient
select public.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.t('patient sees her own notes', true,
  (select count(*) from public.diary_notes)=2);
do $$ declare n int; begin
  update public.diary_notes set body='Regretted it by nine.' where title='Curry';
  get diagnostics n = row_count;
  perform pg_temp.t('patient can edit her own note', true, n=1);
end $$;
do $$ declare n int; begin
  delete from public.diary_notes where title='Curry';
  get diagnostics n = row_count;
  perform pg_temp.t('patient can delete her own note', true, n=1);
end $$;

-- ------------------------------------------------------------- another patient
select public.act_as('22222222-2222-2222-2222-222222222222');
select pg_temp.t('patient cannot read another patient''s notes', true,
  (select count(*) from public.diary_notes)=0);
do $$ declare n int; begin
  delete from public.diary_notes;
  get diagnostics n = row_count;
  perform pg_temp.t('patient cannot delete another patient''s notes', true, n=0);
end $$;
do $$ declare ok boolean := false; begin
  begin insert into public.diary_notes (user_id,body) values
    ('11111111-1111-1111-1111-111111111111','Planted.');
  exception when others then ok := true; end;
  perform pg_temp.t('patient cannot write into another patient''s notes', true, ok);
end $$;

-- --------------------------------------------------------------------- nurse
-- This is the assertion that defends the word on the button.
select public.act_as('33333333-3333-3333-3333-333333333333');
select pg_temp.t('a NURSE cannot read a private note', true,
  (select count(*) from public.diary_notes)=0);
do $$ declare n int; begin
  update public.diary_notes set body='seen';
  get diagnostics n = row_count;
  perform pg_temp.t('a nurse cannot edit a private note', true, n=0);
end $$;

reset role;
select pg_temp.t('the surviving note is still there for its owner', true,
  (select count(*) from public.diary_notes)=1);
