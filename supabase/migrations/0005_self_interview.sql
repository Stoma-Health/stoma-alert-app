-- Stoma Alert — richer daily self-interview ("How are things today?")
-- Keeps the four numeric scores (output, skin, comfort, mood) so the nurse
-- caseload, trends and wellbeing score keep working — skin & output are now
-- DERIVED from the detailed answers. The full structured answers live in `details`.
-- Run this in Supabase → SQL Editor, or let the GitHub integration apply it.

alter table public.check_ins
  add column if not exists details jsonb;

comment on column public.check_ins.details is
  'Full structured self-interview answers (symptoms, abdomen, skin/stoma detail, bleeding, discharge). The four numeric columns are derived from this for trend continuity.';
