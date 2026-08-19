// Scheduled photo purge — enforces the retention rule defined in migration 0016.
//
// Runs on Vercel Cron. No dependencies on purpose: the rest of this repo has no
// build step, and adding one for a single scheduled job would be a poor trade.
// Plain fetch against Supabase's REST and Storage APIs.
//
// DELETION IS OFF BY DEFAULT. Without PURGE_ARMED=true this reports what it
// WOULD remove and touches nothing. Arm it only after reading a real dry run.
//
// Environment:
//   SUPABASE_URL                (defaults to the project this app talks to)
//   SUPABASE_SERVICE_ROLE_KEY   required — the only key that may delete storage
//   CRON_SECRET                 required — Vercel sends it as a Bearer token
//   PURGE_ARMED                 'true' to actually delete. Anything else = dry run.
//
// NOTE: this deliberately does NOT call public.expired_photos(). That function is
// gated on public.is_admin(), which reads auth.uid() — and the service-role key
// has no user, so auth.uid() is null and the function would return zero rows
// forever. A purge that silently does nothing while reporting success is worse
// than no purge at all, so the cutoff is computed here instead.

const DEFAULT_URL = 'https://yevndoekwgahvvskiplt.supabase.co'
const BUCKET = 'diary-photos'

// A cap per run. If something has gone wrong and a million rows look expired,
// this bounds the damage to one batch and leaves evidence in the logs.
const MAX_PER_RUN = 500

/** Retention period, read from the same setting the app shows patients. */
export async function getRetentionMonths(fetchImpl, base, headers) {
  const res = await fetchImpl(
    `${base}/rest/v1/app_settings?key=eq.photo_retention_months&select=value`,
    { headers }
  )
  if (!res.ok) throw new Error(`could not read retention setting: HTTP ${res.status}`)
  const rows = await res.json()
  const months = Number(rows?.[0]?.value)
  // No silent fallback to a default here. If the setting is missing or nonsense,
  // the honest response is to stop, not to invent a retention period and start
  // deleting patient photographs against it.
  if (!Number.isInteger(months) || months < 1) {
    throw new Error(`photo_retention_months is missing or invalid: ${JSON.stringify(rows?.[0]?.value)}`)
  }
  return months
}

/** The date before which an unpinned photo has outlived its retention. */
export function cutoffFor(months, now = new Date()) {
  const d = new Date(now.getTime())
  d.setUTCMonth(d.getUTCMonth() - months)
  return d
}

export async function findExpired(fetchImpl, base, headers, cutoff) {
  const q = new URLSearchParams({
    select: 'id,user_id,path,created_at',
    keep: 'eq.false',
    created_at: `lt.${cutoff.toISOString()}`,
    order: 'created_at.asc',
    limit: String(MAX_PER_RUN),
  })
  const res = await fetchImpl(`${base}/rest/v1/diary_photos?${q}`, { headers })
  if (!res.ok) throw new Error(`could not list expired photos: HTTP ${res.status}`)
  return res.json()
}

/**
 * Files first, then rows.
 *
 * A row deleted before its file leaves an orphan in the bucket that nothing
 * references and nobody will ever find again — it would sit there holding
 * patient data past its retention date, which is the exact thing this job
 * exists to prevent. So if the storage delete fails, the rows stay put and we
 * try again tomorrow.
 */
export async function purge(fetchImpl, base, headers, rows) {
  if (!rows.length) return { files: 0, records: 0 }

  const storageRes = await fetchImpl(`${base}/storage/v1/object/${BUCKET}`, {
    method: 'DELETE',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefixes: rows.map((r) => r.path) }),
  })
  if (!storageRes.ok) {
    throw new Error(
      `storage delete failed (HTTP ${storageRes.status}) — rows left intact, will retry next run`
    )
  }

  const ids = rows.map((r) => r.id).join(',')
  const rowRes = await fetchImpl(`${base}/rest/v1/diary_photos?id=in.(${ids})`, {
    method: 'DELETE',
    headers: { ...headers, Prefer: 'return=minimal' },
  })
  if (!rowRes.ok) {
    // The files are already gone, so this is the bad case: it must be loud.
    throw new Error(
      `FILES DELETED BUT ROWS REMAIN (HTTP ${rowRes.status}) — ${ids.split(',').length} orphaned rows need clearing by hand`
    )
  }
  return { files: rows.length, records: rows.length }
}

export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const base = process.env.SUPABASE_URL || DEFAULT_URL
  const armed = process.env.PURGE_ARMED === 'true'

  // Fail closed on configuration. An unauthenticated endpoint that deletes
  // health data is not something to leave open by accident.
  if (!secret) return res.status(500).json({ error: 'CRON_SECRET is not set' })
  if (req.headers.authorization !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'unauthorized' })
  }
  if (!key) return res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY is not set' })

  const headers = { apikey: key, Authorization: `Bearer ${key}` }

  try {
    const months = await getRetentionMonths(fetch, base, headers)
    const cutoff = cutoffFor(months)
    const rows = await findExpired(fetch, base, headers, cutoff)

    if (!armed) {
      return res.status(200).json({
        mode: 'dry-run',
        note: 'Nothing was deleted. Set PURGE_ARMED=true to enable.',
        retention_months: months,
        cutoff: cutoff.toISOString(),
        would_delete: rows.length,
        capped_at: MAX_PER_RUN,
        sample: rows.slice(0, 10).map((r) => ({ path: r.path, created_at: r.created_at })),
      })
    }

    const result = await purge(fetch, base, headers, rows)
    console.log(`[purge] retention ${months}m, cutoff ${cutoff.toISOString()}, removed ${result.records}`)
    return res.status(200).json({
      mode: 'armed',
      retention_months: months,
      cutoff: cutoff.toISOString(),
      ...result,
      more_remaining: rows.length === MAX_PER_RUN,
    })
  } catch (err) {
    // Loud, and a non-200 so Vercel records it as a failed cron run rather than
    // a quiet success with nothing done.
    console.error('[purge] failed:', err?.message || err)
    return res.status(500).json({ error: String(err?.message || err) })
  }
}
