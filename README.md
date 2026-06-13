# Stoma Alert — installable PWA (concept preview)

Full-screen, installable mobile preview of the Stoma Alert patient app. Seven working
screens (Home, Check-in, Messages, Learn, Supplies, Capture, Progress) with bottom-tab
navigation, an app-shell service worker (works offline once loaded), web manifest and icons.

**Status:** concept preview / non-diagnostic. Looks shippable; not wired to live data.
Static site — no build step.

## Get it onto your GitHub + Vercel

**1. Create the repo (your GitHub)**
- New repo, e.g. `stoma-alert-app`
- Upload the contents of this folder to the repo **root** (everything except `_extras/`).
  Either drag-drop in the GitHub web UI, or `git init && git add . && git commit && git push`.

**2. Deploy on Vercel (your account)**
- Vercel → **Add New… → Project** → import the new repo
- **Root Directory → `./`** (the app sits at the repo root)
- **Framework Preset → Other** (static site; leave build/output blank)
- Deploy → your install link is the deployment URL (e.g. `stoma-alert.vercel.app`)

`vercel.json` already sets the service-worker cache header and the manifest content-type,
so installability works out of the box. To install on a phone: open the URL →
Share → **Add to Home Screen**.

## Files
- `index.html` — the app (single file, vanilla JS tab nav)
- `manifest.webmanifest` — PWA manifest (scoped to `/` = served at the domain root)
- `sw.js` — app-shell service worker
- `icons/` — 192 / 512 / maskable / apple-touch-icon
- `vercel.json` — SW cache + manifest content-type headers
- `.vercelignore` — keeps `_extras/` out of the deploy
- `_extras/` — **not deployed**: the mobile architecture brief (HTML + PDF) and the QR card

> Keep all on-screen copy inside the non-diagnostic frame.
