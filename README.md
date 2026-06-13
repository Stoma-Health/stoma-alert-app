# Stoma Alert — working prototype (test data only)

A real, installable app wired to Supabase. **Not for real patients** — test data only,
no clinical/compliance layer.

- `index.html` — the working app (login + check-ins + nurse caseload), talks to Supabase
  directly from the browser. No build step.
- `preview.html` — the original non-functional concept mock-up (kept for reference).
- `supabase/migrations/0001_init.sql` — database schema + security rules.
- `manifest.webmanifest`, `sw.js`, `icons/` — PWA bits (installable, offline shell).

## One-time Supabase setup
1. **Run the schema:** Supabase → SQL Editor → paste `supabase/migrations/0001_init.sql` → Run.
2. **Allow instant test signups:** Supabase → Authentication → Sign In/Providers → Email →
   turn **OFF "Confirm email"** (so test accounts work without an email round-trip).

## Use it
- Create a **Patient** account → do a daily check-in (it saves to the database) → see it in “Diary”.
- Create a **Nurse** account (different email) → see everyone's check-ins in the caseload,
  flagged by their lowest score.

## Deploy
Static site, no build — drag-drop the folder to Vercel, or connect Git. Config (Supabase URL +
publishable key) is embedded in `index.html`; the publishable key is safe to ship publicly (RLS-protected).
