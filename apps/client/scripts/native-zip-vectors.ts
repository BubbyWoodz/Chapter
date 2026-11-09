// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native ZIP reader: archives written by fflate (what the web
// importer reads with unzipSync) at every compression level, and the exact member
// order unzipSync returns.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { zipSync, unzipSync, strToU8 } from 'fflate';

function prng(seed: number): () => number { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s >>> 24; }; }
export function verifyZip(write: boolean): void {
  const r = prng(7);
  const noise = Uint8Array.from({ length: 12000 }, r);
  const text = strToU8('Day One journal entry. '.repeat(1500) + 'Ünïcødé ✓ 😀\n'.repeat(120));
  const tiny = strToU8('ab');
  // Literals plus copies at every distance/length band, so each DEFLATE length and distance code is exercised.
  const varied: number[] = [];
  for (let k = 0; varied.length < 60000; k++) {
    if (varied.length < 300 || r() < 90) { varied.push(r()); continue; }
    const dist = 1 + ((r() << 8 | r()) % Math.min(32768, varied.length)), len = 3 + (r() % 256);
    for (let j = 0; j < len; j++) varied.push(varied[varied.length - dist]);
  }
  const archives = [0, 1, 6, 9].map((level) => {
    const zip = zipSync({
      'Journal.json': [strToU8(JSON.stringify({ entries: [{ text: '# Hi', uuid: 'U1' }] })), { level }],
      'photos/': new Uint8Array(0),
      'photos/0123456789abcdef.jpeg': [noise, { level }],
      'Export/videos/abc.mov': [text, { level }],
      '12': [tiny, { level }],
      'varied.bin': [Uint8Array.from(varied.slice(0, 60000)), { level }],
      'Résumé 日本.txt': [strToU8('naïve'), { level }],
      'empty.txt': [new Uint8Array(0), { level }],
    });
    const files = Object.entries(unzipSync(zip)).map(([name, data]) => ({ name, size: data.length, base64: Buffer.from(data).toString('base64') }));
    return { level, zip: Buffer.from(zip).toString('base64'), files };
  });
  const fixture = { archives };
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/zip-reader.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), fixture, 'Native ZIP vectors must equal fflate');
  console.log(`Native ZIP reader vectors equal fflate unzipSync (${archives.length} archives, levels 0/1/6/9).`);
}
