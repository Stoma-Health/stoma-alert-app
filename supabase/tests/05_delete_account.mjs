/**
 * Account deletion logic.
 *
 * The parts worth proving are the ones that would be quiet disasters: deleting
 * the wrong person, or deleting the account while their photographs survive.
 *
 * Run: node supabase/tests/05_delete_account.mjs
 */
import { whoAmI, listUserFiles } from '../../api/delete-account.js'

let failed = 0
const t = (label, ok) => { console.log(`${ok ? 'PASS' : '*** FAIL ***'}  ${label}`); if (!ok) failed++ }
const ok = (body) => ({ ok: true, status: 200, json: async () => body })
const bad = (status) => ({ ok: false, status, json: async () => ({}) })

// ---- identity ----
t('a valid token identifies the caller',
  (await whoAmI(async () => ok({ id: 'user-1' }), '', 'k', 't'))?.id === 'user-1')
t('a rejected token is nobody',
  (await whoAmI(async () => bad(401), '', 'k', 't')) === null)
t('a 200 with no id is still nobody',
  (await whoAmI(async () => ok({}), '', 'k', 't')) === null)

// The token is what gets sent, not anything from a request body.
{
  let sent = null
  await whoAmI(async (u, o) => { sent = o.headers.Authorization; return ok({ id: 'x' }) }, '', 'k', 'the-token')
  t('the caller\'s own token is used to identify them', sent === 'Bearer the-token')
}

// ---- files ----
{
  let body = null
  const paths = await listUserFiles(async (u, o) => {
    body = JSON.parse(o.body)
    return ok([{ name: 'a.jpg' }, { name: 'b.jpg' }, { name: null }])
  }, '', {}, 'user-1')
  t('files are looked up under the user\'s own folder', body.prefix === 'user-1')
  t('paths are prefixed with the user id',
    paths.length === 2 && paths[0] === 'user-1/a.jpg' && paths[1] === 'user-1/b.jpg')
  t('entries without a name are ignored', !paths.includes('user-1/null'))
}
{
  const paths = await listUserFiles(async () => ok(null), '', {}, 'user-1')
  t('a user with no photos yields no paths', Array.isArray(paths) && paths.length === 0)
}
{
  let threw = false
  try { await listUserFiles(async () => bad(500), '', {}, 'u') } catch { threw = true }
  t('a failed listing throws rather than reporting nothing to delete', threw)
}

console.log(failed ? `\n${failed} failing.` : `\nAll checks passed.`)
process.exit(failed ? 1 : 0)
