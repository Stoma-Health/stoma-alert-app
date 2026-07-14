# Stoma Alert — Production readiness to-do

Running list of what must be addressed **before this prototype handles real patients**.
The app currently declares "test data only · not for real patients" — these items clear that bar.

_Last updated: 2026-07-14._

---

## 1. Photo storage & retention

Photos are the main thing that scales (see below). Files live in **Supabase Storage**
bucket `diary-photos`; the `diary_photos` table holds only a small metadata row each.
Already compressed client-side to **max 1600px, JPEG q0.85** (~200–400 KB/photo).

- [ ] **Retention policy** — auto-delete or archive photos older than a set period (e.g. 12 months). *Highest priority — do this first.*
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

## 3. Auth & access hardening (currently prototype-grade)

- [ ] **Role is self-selected at signup** (patient/nurse/admin in `user_metadata`) and **not enforced server-side**. Move to an enforced roles table + tightened RLS; remove self-service nurse/admin signup in favour of invite/assignment.
- [ ] Admin **Content editor** article bodies accept **raw HTML** (admin is trusted today) — sanitise or restrict before untrusted admins exist.
- [ ] Review all RLS policies for least-privilege before go-live.

## 4. General

- [ ] Replace "test data only" banner once the above are cleared.
- [ ] Seed/clean data: remove duplicate test accounts.
- [ ] Facebook community link still a placeholder (WhatsApp is live).
