// A minimal ZIP writer, store method (no compression).
//
// Written by hand rather than pulled in as a dependency because the rest of this
// app has no build step, and a data export is not worth breaking that for. JPEGs
// are already compressed, so storing them costs nothing but a few bytes of
// header — deflate would add risk for no real saving.
//
// Exported as its own module so it can be tested in Node against the real
// `unzip` binary. A data export that produces a corrupt archive is worse than no
// export at all: the patient only finds out later, when they try to open it.

const CRC_TABLE = (() => {
  const t = new Uint32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c >>> 0
  }
  return t
})()

export function crc32(bytes) {
  let c = 0xffffffff
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

/** MS-DOS date and time, which is what ZIP stores. Seconds have 2s resolution. */
function dosDateTime(d) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()
  return { time, date }
}

/**
 * Build a ZIP from [{ name, data: Uint8Array }].
 *
 * Returns a Uint8Array. Names are stored UTF-8 with the language-encoding flag
 * set, so accented filenames survive.
 */
export function makeZip(entries, now = new Date()) {
  const enc = new TextEncoder()
  const { time, date } = dosDateTime(now)
  const locals = []
  const centrals = []
  let offset = 0

  for (const entry of entries) {
    const name = enc.encode(entry.name)
    const data = entry.data
    const crc = crc32(data)

    const local = new Uint8Array(30 + name.length)
    const lv = new DataView(local.buffer)
    lv.setUint32(0, 0x04034b50, true)   // local file header signature
    lv.setUint16(4, 20, true)           // version needed
    lv.setUint16(6, 0x0800, true)       // flags: UTF-8 names
    lv.setUint16(8, 0, true)            // method: store
    lv.setUint16(10, time, true)
    lv.setUint16(12, date, true)
    lv.setUint32(14, crc, true)
    lv.setUint32(18, data.length, true) // compressed size
    lv.setUint32(22, data.length, true) // uncompressed size
    lv.setUint16(26, name.length, true)
    lv.setUint16(28, 0, true)           // extra field length
    local.set(name, 30)

    const central = new Uint8Array(46 + name.length)
    const cv = new DataView(central.buffer)
    cv.setUint32(0, 0x02014b50, true)   // central directory signature
    cv.setUint16(4, 20, true)           // version made by
    cv.setUint16(6, 20, true)           // version needed
    cv.setUint16(8, 0x0800, true)
    cv.setUint16(10, 0, true)
    cv.setUint16(12, time, true)
    cv.setUint16(14, date, true)
    cv.setUint32(16, crc, true)
    cv.setUint32(20, data.length, true)
    cv.setUint32(24, data.length, true)
    cv.setUint16(28, name.length, true)
    cv.setUint16(30, 0, true)           // extra
    cv.setUint16(32, 0, true)           // comment
    cv.setUint16(34, 0, true)           // disk number
    cv.setUint16(36, 0, true)           // internal attrs
    cv.setUint32(38, 0, true)           // external attrs
    cv.setUint32(42, offset, true)      // offset of local header
    central.set(name, 46)

    locals.push(local, data)
    centrals.push(central)
    offset += local.length + data.length
  }

  const centralSize = centrals.reduce((n, c) => n + c.length, 0)
  const end = new Uint8Array(22)
  const ev = new DataView(end.buffer)
  ev.setUint32(0, 0x06054b50, true)     // end of central directory
  ev.setUint16(8, entries.length, true) // entries on this disk
  ev.setUint16(10, entries.length, true)
  ev.setUint32(12, centralSize, true)
  ev.setUint32(16, offset, true)        // offset of central directory

  const total = offset + centralSize + end.length
  const out = new Uint8Array(total)
  let p = 0
  for (const part of [...locals, ...centrals, end]) { out.set(part, p); p += part.length }
  return out
}

/**
 * Reduce a filename to plain ASCII.
 *
 * The writer stores UTF-8 names correctly and sets the language-encoding flag —
 * verified. But Info-ZIP's `unzip` 6.00, still the default on many Linux boxes,
 * ignores that flag and mangles the name on extraction. A patient exporting
 * their own medical records should not have to care which unzip they have, and
 * we generate these names ourselves, so the simplest fix is to not create the
 * problem.
 */
export function safeName(s) {
  return (s || '')
    .normalize('NFKD')                    // é -> e + combining accent
    .replace(/[̀-ͯ]/g, '')      // drop the accents
    .replace(/[^A-Za-z0-9._/-]+/g, '-')   // anything else becomes a dash
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    || 'file'
}
