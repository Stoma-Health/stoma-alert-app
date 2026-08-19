# Stoma Alert — Production readiness to-do

Running list of what must be addressed **before this prototype handles real patients**.
The app currently declares "test data only · not for real patients" — these items clear that bar.

_Last updated: 2026-08-19._

---

## 1. Photo storage & retention

Photos are the main thing that scales (see below). Files live in **Supabase Storage**
bucket `diary-photos`; the `diary_photos` table holds only a small metadata row each.
Already compressed client-side to **max 1600px, JPEG q0.85** (~200–400 KB/photo).

- [~] **Retention policy** — *rule defined and tested (`0016_photo_retention.sql`); NOT yet armed.*
      `app_settings.photo_retention_months` (default 12) is the documented, dated, changeable
      period. `diary_photos.keep` lets a patient exempt individual photos — the oldest photo is
      often the clinically important one, because that is what shows a hernia developing.
      `expired_photos()` (admin-only) lists what a purge would remove; `my_photos_expiring_within()`
      warns a patient while they can still act. **Nothing deletes anything yet** — the file lives in
      Supabase Storage and only the service-role key can remove it, so the purge runner is a
      separate, deliberate decision. Runner built: `api/purge-photos.js` on **Vercel Cron**, daily 03:00 UTC, **dry run until
      `PURGE_ARMED=true`**. Outstanding: set `SUPABASE_SERVICE_ROLE_KEY` + `CRON_SECRET` in Vercel,
      read one real dry run, then arm. UI toggle for `keep` also to do.
- [ ] **Thumbnails** — store a small thumb for grid views; fetch full-res only on tap (cuts bandwidth).
- [ ] Consider dropping to **1280px / q0.80** to roughly halve storage with little visible loss.
- [ ] At scale, evaluate moving the bucket to cheaper object storage (Cloudflare R2 / Hetzner) — same app, different backend.
- [ ] Remove the temporary fetch caps once pagination exists (Progress photos = 24, Capture diary = 60, check-ins = 1000).

**Rough scale:** ~250 KB/photo → ~4,000 photos/GB. Supabase free = 1 GB; Pro includes 100 GB (~400k photos), then ~$0.02/GB/mo.

## 2. GDPR / data protection (UK GDPR — special-category health data, Art. 9)

Stoma photos + symptom check-ins are **special-category health data**, so the bar is high.

- [ ] **Lawful basis + explicit consent** for processing health data (Art. 6 + Art. 9); consent capture in the signup/onboarding flow.
- [ ] **Privacy notice** — what's collected, why, how long kept, who it's shared with (care team), patient rights.
- [ ] **DPIA** (Data Protection Impact Assessment) — required for large-scale special-category processing.
- [ ] **Data subject rights** — access, rectification, **erasure ("delete my account & data")**, portability/export.
- [ ] **Retention schedule** — documented, and technically enforced (ties to photo retention above).
- [ ] **Data Processing Agreement** with Supabase (and any sub-processors); confirm **UK/EU data residency** for the Supabase project.
- [ ] **Encryption** in transit (HTTPS ✓) and at rest (confirm Supabase); signed URLs already expire (1 h).
- [ ] **Breach procedure** + records of processing (ROPA).
- [ ] If NHS-facing: **NHS Data Security & Protection Toolkit (DSPT)** and Caldicott principles.
- [ ] Clinical-safety framing: app is **non-diagnostic** (already worded throughout) — keep, and check DCB0129/0160 if it becomes a medical device.

## 3. Auth & access hardening

- [x] **Role is self-selected at signup and not enforced server-side.** *Done — `0015_server_side_roles.sql`.*
      This was worse than "unenforced": all 20 policies read `auth.jwt() -> user_metadata ->> 'role'`,
      and **`user_metadata` is writable by the user**. Any patient could run
      `supabase.auth.updateUser({ data:{ role:'nurse' } })` in the browser console and read every
      other patient's check-ins, stoma photos, messages and profile. Demonstrated against a local
      copy of the schema before fixing.
      Roles now live in `public.user_roles`, which clients cannot write; a trigger assigns
      `patient` on signup regardless of what the form sends; policies ask the table via
      `is_nurse()` / `is_admin()`. Nurse and admin are granted only in the SQL editor.
      `supabase/tests/run.sh` replays the attack against a throwaway Postgres — 20 assertions.
- [ ] Admin **Content editor** article bodies accept **raw HTML** (admin is trusted today) — sanitise or restrict before untrusted admins exist.
- [ ] Review all RLS policies for least-privilege before go-live.

## 4. General

- [ ] Replace "test data only" banner once the above are cleared.
- [ ] Seed/clean data: remove duplicate test accounts.
- [ ] Facebook community link still a placeholder (WhatsApp is live).
