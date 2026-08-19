/**
 * ZIP writer.
 *
 * Verified against the real `unzip` binary, not just against itself: a hand
 * written archive format that only my own reader can open would be worthless to
 * a patient who exports their data and tries to open it on a Mac.
 *
 * Run: node supabase/tests/04_zip.mjs
 */
import { writeFileSync, mkdtempSync, readFileSync } from 'fs'
import { execSync } from 'child_process'
import { tmpdir } from 'os'
import { join } from 'path'
import { copyFileSync } from 'fs'

// zip.js is served to the browser as .js; Node needs .mjs to treat it as ESM.
const dir = mkdtempSync(join(tmpdir(), 'stoma-zip-'))
copyFileSync(new URL('../../zip.js', import.meta.url), join(dir, 'zip.mjs'))
const { makeZip, crc32, safeName } = await import(join(dir, 'zip.mjs'))

let failed = 0
const t = (label, ok) => { console.log(`${ok ? 'PASS' : '*** FAIL ***'}  ${label}`); if (!ok) failed++ }

// A known CRC32, so a broken table is caught here rather than by a user.
t('crc32 of "123456789" is 0xCBF43926',
  crc32(new TextEncoder().encode('123456789')) === 0xcbf43926)

const enc = new TextEncoder()
const jpeg = new Uint8Array(5000).map((_, i) => (i * 7) % 256)   // stand-in binary
const entries = [
  { name: 'data.json', data: enc.encode(JSON.stringify({ hello: 'world', n: 42 })) },
  { name: 'photos/stoma-2026-01-02.jpg', data: jpeg },
  { name: 'photos/' + safeName('accentué-café.jpg'), data: enc.encode('not really a jpeg') },
]
const zip = makeZip(entries, new Date('2026-08-19T19:45:00Z'))
const path = join(dir, 'export.zip')
writeFileSync(path, zip)

t('archive is not empty', zip.length > 100)

// The real test: can a standard tool read it?
let listed = '', tested = '', ok = true
try {
  tested = execSync(`unzip -t ${path}`, { encoding: 'utf8' })
  listed = execSync(`unzip -l ${path}`, { encoding: 'utf8' })
} catch (e) { ok = false; console.log(e.stdout || e.message) }

t('unzip -t reports no errors', ok && /No errors detected/.test(tested))
t('all three files are listed', /data\.json/.test(listed) &&
  /stoma-2026-01-02\.jpg/.test(listed) && /accentue-cafe\.jpg/.test(listed))

execSync(`cd ${dir} && unzip -o -q ${path} -d out`)
const back = JSON.parse(readFileSync(join(dir, 'out/data.json'), 'utf8'))
t('json round-trips exactly', back.hello === 'world' && back.n === 42)

const backJpeg = readFileSync(join(dir, 'out/photos/stoma-2026-01-02.jpg'))
t('binary round-trips byte for byte',
  backJpeg.length === jpeg.length && backJpeg.every((b, i) => b === jpeg[i]))

t('nested folder survives', readFileSync(join(dir, 'out/photos/accentue-cafe.jpg'), 'utf8') === 'not really a jpeg')

// Names are stored as UTF-8 with the language flag set — that part is correct.
// safeName exists because Info-ZIP unzip 6.00 ignores the flag and mangles the
// name on extraction, and a patient should not need a modern unzip to read their
// own medical records.
{
  const z = makeZip([{ name: 'café.jpg', data: new Uint8Array([1, 2, 3]) }])
  const dv = new DataView(z.buffer)
  t('the UTF-8 language flag is set', (dv.getUint16(6, true) & 0x800) !== 0)
  t('a UTF-8 name is stored as UTF-8 bytes',
    new TextDecoder('utf-8').decode(z.slice(30, 30 + dv.getUint16(26, true))) === 'café.jpg')
  t('safeName strips accents rather than dropping the word',
    safeName('café-über_2.jpg') === 'cafe-uber_2.jpg')
  t('safeName never returns an empty name', safeName('***') === 'file' && safeName('') === 'file')
  t('safeName keeps folder separators', safeName('photos/a b.jpg') === 'photos/a-b.jpg')
}

// An empty export must still be a valid archive, not a truncated file.
const empty = makeZip([], new Date('2026-08-19T19:45:00Z'))
writeFileSync(join(dir, 'empty.zip'), empty)
let emptyOk = true
try { execSync(`unzip -t ${join(dir, 'empty.zip')}`, { encoding: 'utf8' }) }
catch (e) { emptyOk = /Empty zipfile|zipfile is empty/.test((e.stdout || '') + (e.stderr || '')) }
t('an empty archive is still well-formed', emptyOk)

console.log(failed ? `\n${failed} failing.` : `\nAll checks passed.`)
process.exit(failed ? 1 : 0)
