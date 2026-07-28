-- Stoma Alert — expand patient profile stoma details.
-- Adds Jejunostomy as a valid stoma type and stores whether the stoma is
-- temporary or permanent for existing installs.

alter table public.patient_profile
  drop constraint if exists patient_profile_stoma_type_check;

alter table public.patient_profile
  add constraint patient_profile_stoma_type_check
  check (stoma_type in ('Ileostomy','Colostomy','Urostomy','Jejunostomy'));

alter table public.patient_profile
  add column if not exists stoma_duration text;

alter table public.patient_profile
  drop constraint if exists patient_profile_stoma_duration_check;

alter table public.patient_profile
  add constraint patient_profile_stoma_duration_check
  check (stoma_duration in ('Temporary','Permanent'));
