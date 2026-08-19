// Right to erasure — UK GDPR Art. 17.
//
// A patient can delete their own rows through RLS, but they cannot delete their
// own auth record or their files in Storage: both need the service-role key. So
// this endpoint does the parts the browser cannot, and only ever for the person
// asking.
//
// It is NOT protected by CRON_SECRET. It is protected by the caller's own access
// token: whoever you are according to Supabase is whose account gets deleted.
// There is no user id in the request body on purpose — if there were, someone
// would eventually pass a different one.
//
// Environment: SUPABASE_SERVICE_ROLE_KEY, and optionally SUPABASE_URL.

const DEFAULT_URL = 'https://yevndoekwgahvvskiplt.supabase.co'
const BUCKET = 'diary-photos'

/** Who is this, according to Supabase? Null if the token is bad or expired. */
export async function whoAmI(fetchImpl, base, anonKeyOrToken, accessToken) {
  const res = await fetchImpl(`${base}/auth/v1/user`, {
    headers: { apikey: anonKeyOrToken, Authorization: `Bearer ${accessToken}` },
  })
  if (!res.ok) return null
  const user = await res.json()
  return user?.id ? user : null
}

/** Every stored object belonging to this user. Their id is the folder name. */
export async function listUserFiles(fetchImpl, base, headers, userId) {
  const res = await fetchImpl(`${base}/storage/v1/object/list/${BUCKET}`, {
    method: 'POST',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefix: userId, limit: 1000, offset: 0 }),
  })
  if (!res.ok) throw new Error(`could not list files: HTTP ${res.status}`)
  const items = await res.json()
  return (items || []).filter((i) => i?.name).map((i) => `${userId}/${i.name}`)
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' })

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const base = process.env.SUPABASE_URL || DEFAULT_URL
  if (!key) return res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY is not set' })

  const auth = req.headers.authorization || ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return res.status(401).json({ error: 'sign in first' })

  const headers = { apikey: key, Authorization: `Bearer ${key}` }

  try {
    // Identity comes from the token, never from the request body.
    const user = await whoAmI(fetch, base, key, token)
    if (!user) return res.status(401).json({ error: 'session expired, please sign in again' })

    // Files first. Deleting the auth record cascades every row, including the
    // one naming each file — do that first and the images become unreachable
    // orphans holding the patient's data after they asked for it to be erased.
    const paths = await listUserFiles(fetch, base, headers, user.id)
    if (paths.length) {
      const del = await fetch(`${base}/storage/v1/object/${BUCKET}`, {
        method: 'DELETE',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: paths }),
      })
      if (!del.ok) {
        throw new Error(`could not delete photos (HTTP ${del.status}) — account left intact`)
      }
    }

    // Threads are keyed by thread_user, which has no foreign key, so the cascade
    // will not take them. A patient's messages must go with the patient.
    const msgs = await fetch(`${base}/rest/v1/messages?thread_user=eq.${user.id}`, {
      method: 'DELETE',
      headers: { ...headers, Prefer: 'return=minimal' },
    })
    if (!msgs.ok) throw new Error(`could not delete messages: HTTP ${msgs.status}`)

    // Now the account. Everything else cascades from auth.users.
    const gone = await fetch(`${base}/auth/v1/admin/users/${user.id}`, {
      method: 'DELETE',
      headers,
    })
    if (!gone.ok) {
      throw new Error(`photos and messages deleted but the account remains (HTTP ${gone.status}) — needs clearing by hand`)
    }

    console.log(`[delete-account] erased ${user.id}, ${paths.length} files`)
    return res.status(200).json({ deleted: true, files: paths.length })
  } catch (err) {
    console.error('[delete-account] failed:', err?.message || err)
    return res.status(500).json({ error: String(err?.message || err) })
  }
}
