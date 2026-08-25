# Stoma Alert — working prototype (test data only)

A real, installable app wired to Supabase. **Not for real patients** — test data only,
no clinical/compliance layer.

- `index.html` — the working app (login + check-ins + nurse caseload), talks to Supabase
  directly from the browser. No build step.
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

## Scheduled photo purge

`api/purge-photos.js` enforces the retention rule from `0016_photo_retention.sql`.
Vercel Cron calls it daily at 03:00 UTC (`vercel.json` → `crons`).

**It deletes nothing until it is armed.** Without `PURGE_ARMED=true` it reports what
it would remove and stops. Read a real dry run before arming it.

Environment variables, set in Vercel → Settings → Environment Variables:

| Variable | Needed | Notes |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | yes | The only key that may delete storage objects. **Never put this in `index.html`** — it bypasses every RLS policy. |
| `CRON_SECRET` | yes | Any long random string. Vercel sends it as `Authorization: Bearer …`; the endpoint rejects anything else, so it cannot be triggered from outside. |
| `PURGE_ARMED` | no | `true` to actually delete. Anything else, including unset, is a dry run. |
| `SUPABASE_URL` | no | Defaults to this project's URL. |

Dry run by hand:

```bash
curl -H "Authorization: Bearer $CRON_SECRET" https://stoma-alert-app.vercel.app/api/purge-photos
```

Note it does **not** call `public.expired_photos()`. That function is gated on
`is_admin()`, which reads `auth.uid()` — and the service-role key has no user, so it
would return zero rows forever: a purge that silently does nothing while reporting
success. The cutoff is computed in the job instead.
