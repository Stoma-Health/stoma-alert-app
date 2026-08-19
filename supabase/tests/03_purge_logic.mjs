/**
 * Purge runner logic.
 *
 * The database rules are proven in SQL; this covers the parts that live in the
 * job itself and would otherwise only be discovered in production: the cutoff
 * date, the refusal to guess a retention period, and the order of deletion.
 *
 * Run: node supabase/tests/03_purge_logic.mjs
 */
import { getRetentionMonths, cutoffFor, findExpired, purge } from '../../api/purge-photos.js'

let failed = 0
const t = (label, ok) => {
  console.log(`${ok ? 'PASS' : '*** FAIL ***'}  ${label}`)
  if (!ok) failed++
}
const ok = (body) => ({ ok: true, status: 200, json: async () => body })
const bad = (status) => ({ ok: false, status, json: async () => ({}) })

// ---- cutoff ----
const jan = new Date('2026-08-19T12:00:00Z')
t('12 months back from Aug 2026 is Aug 2025',
  cutoffFor(12, jan).toISOString().startsWith('2025-08-19'))
t('6 months back crosses the year end correctly',
  cutoffFor(6, new Date('2026-02-15T00:00:00Z')).toISOString().startsWith('2025-08-15'))
t('24 months back is two years',
  cutoffFor(24, jan).toISOString().startsWith('2024-08-19'))

// ---- retention setting ----
t('reads the configured period',
  await getRetentionMonths(async () => ok([{ value: 12 }]), '', {}) === 12)
for (const badValue of [null, undefined, 0, -3, 'soon', {}]) {
  let threw = false
  try { await getRetentionMonths(async () => ok([{ value: badValue }]), '', {}) }
  catch { threw = true }
  t(`refuses to invent a period when the setting is ${JSON.stringify(badValue)}`, threw)
}
{
  let threw = false
  try { await getRetentionMonths(async () => ok([]), '', {}) } catch { threw = true }
  t('refuses to run when the setting row is missing', threw)
}

// ---- query shape ----
{
  let url = ''
  await findExpired(async (u) => { url = u; return ok([]) }, '', {}, new Date('2025-08-19T00:00:00Z'))
  t('only asks for unpinned photos', url.includes('keep=eq.false'))
  t('only asks for photos older than the cutoff', url.includes('created_at=lt.2025-08-19'))
  t('caps how much one run may remove', url.includes('limit=500'))
}

// ---- deletion order ----
{
  const calls = []
  const rows = [{ id: 'a', path: 'u/1.jpg' }, { id: 'b', path: 'u/2.jpg' }]
  await purge(async (u, o) => { calls.push(`${o?.method || 'GET'} ${u.includes('storage') ? 'storage' : 'rows'}`); return ok({}) }, '', {}, rows)
  t('deletes the files before the rows',
    calls[0] === 'DELETE storage' && calls[1] === 'DELETE rows')
}
{
  const calls = []
  let threw = false
  try {
    await purge(async (u) => { calls.push(u); return u.includes('storage') ? bad(500) : ok({}) },
      '', {}, [{ id: 'a', path: 'u/1.jpg' }])
  } catch { threw = true }
  t('if the file delete fails, it throws', threw)
  t('...and never deletes the row, so nothing is orphaned',
    calls.filter(c => !c.includes('storage')).length === 0)
}
{
  let threw = false, msg = ''
  try {
    await purge(async (u) => u.includes('storage') ? ok({}) : bad(500), '', {}, [{ id: 'a', path: 'u/1.jpg' }])
  } catch (e) { threw = true; msg = e.message }
  t('if the row delete fails after the file is gone, it says so loudly',
    threw && msg.includes('ORPHANED') === false && msg.includes('orphaned'))
}
{
  const r = await purge(async () => { throw new Error('should not be called') }, '', {}, [])
  t('nothing to do means no API calls at all', r.files === 0 && r.records === 0)
}

console.log(failed ? `\n${failed} failing.` : `\nAll checks passed.`)
process.exit(failed ? 1 : 0)
