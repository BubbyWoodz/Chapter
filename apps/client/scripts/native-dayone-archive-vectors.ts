// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of import/dayone.ts parseDayOneArchive, resolve and
// entryMoments: fflate-built exports, including the loose JavaScript edge cases.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { zipSync, strToU8 } from 'fflate';
import { parseDayOneArchive, entryMoments, type DayOneMoment, type MomentKind } from '../src/import/dayone';

const mtime = new Date(Date.UTC(2026, 10, 9, 14, 0, 0));
const j = (v: unknown): Uint8Array => strToU8(JSON.stringify(v));
const b = (s: string): Uint8Array => strToU8(s);
const zip = (files: Record<string, Uint8Array>, level: 0 | 6 = 0): Uint8Array =>
  zipSync(Object.fromEntries(Object.entries(files).map(([k, v]) => [k, [v, { level, mtime }]])));

const travel = {
  metadata: { version: '1.0' },
  entries: [
    {
      uuid: 'E1', text: '# Lisbon\n![](dayone-moment://P1)', creationDate: '2024-05-01T10:00:00Z',
      photos: [
        { identifier: 'P1', md5: 'aaaa1111bbbb2222', type: 'jpeg', width: 4032, height: 3024 },
        { identifier: 'P2', md5: 'up1', type: 'JPEG', width: null, height: 3.5 },
        { identifier: 'P3', md5: 'missing', type: 'png' },
        { identifier: 'K', type: 'png' },
        { identifier: 'P4', md5: ['ab', 'cd'], type: 'jpeg' },
        { identifier: 'P5', md5: 42, type: 'png' },
        { type: 'gif' },
        { identifier: 'P6', md5: 'ctor1', type: 'constructor' },
        { identifier: 'P7', md5: 'proto1', type: '__proto__' },
        { identifier: 'P8', md5: '', type: 'heic' },
        { identifier: '7' },
        { identifier: 'P9', md5: 'aaaa1111bbbb2222', type: 5 },
        3, 'str', [1], true,
        { identifier: 'DUP', md5: 'aaaa1111bbbb2222', type: 'jpeg' },
        { identifier: 'P10', md5: 'zero', type: 'jpeg' },
        { identifier: 12, md5: 'aaaa1111bbbb2222' },
        { identifier: '', md5: 'aaaa1111bbbb2222' },
      ],
      videos: [
        { identifier: 'VID-1', type: 'mov', duration: 1.0005 },
        { identifier: 'VID-2', md5: 'cccc3333', type: 'mov', duration: -0.0004 },
        { identifier: 'DUP', md5: 'cccc3333', type: 'mp4', duration: 0.0025 },
        { identifier: 'VID-3', md5: 'cccc3333', duration: '3' },
        { identifier: 'VID-4', md5: 'cccc3333', duration: 1e308 },
      ],
      audios: [{ identifier: 'AUD-1', md5: 'dddd4444', type: 'm4a', duration: 2.4995 }],
      pdfAttachments: [{ identifier: 'PDF9', type: 'pdf' }, { identifier: 'PDF10', md5: 'nofile' }],
      tags: ['trip', ' ', 3],
    },
    { uuid: 'E2', text: 'plain', photos: 'str', videos: null },
    5, 'text', [], false,
    { uuid: 'E3', text: 'a', photos: [{ identifier: 'Q1', md5: 'dddd4444', type: 'm4a' }] },
  ],
};
const media: Record<string, Uint8Array> = {
  'photos/aaaa1111bbbb2222.jpeg': b('jpeg-first'),
  'Export/photos/aaaa1111bbbb2222.jpeg': b('jpeg-second-wins'),
  'photos/up1.JPEG': b('upper'),
  'photos/\u212A.png': b('kelvin'), // KELVIN SIGN, canonically equivalent to "K" but a different key
  'photos/ab,cd.jpeg': b('array-md5'),
  'photos/42.png': b('number-md5'),
  'photos/undefined.gif': b('template-undefined'),
  'photos/ctor1.constructor': b('ctor'),
  'photos/proto1.__proto__': b('proto'),
  'photos/P8.heic': b('by-identifier'),
  '7': b('array-index-name'),
  'videos/VID-1.mov': b('video-by-identifier-stem'),
  'videos/cccc3333.mov': b('video'),
  'audios/dddd4444.m4a': b('audio'),
  'pdfs/PDF9.pdf': b('pdf'),
  'photos/zero.jpeg': new Uint8Array(0),
  'photos/': new Uint8Array(0),
};
const cases: { label: string; zip: Uint8Array }[] = [
  {
    label: 'main', zip: zip({
      'Travel.json': j(travel),
      ...media,
      'Export/Work.JSON': j({ entries: [{ text: 'work', videos: [{ identifier: 'VID-1', type: 'mov' }] }] }),
      '.json': j({ entries: [] }),
      'metadata.json': j({ version: '1' }),
      'broken.json': b('{not json'),
      'bom.json': b('\uFEFF' + JSON.stringify({ entries: [{ text: 'bom' }] })),
      'arr.json': b('[1,2]'),
      'num.json': b('5'),
      'empty.json': new Uint8Array(0),
      'Caf\u00e9.json': j({ entries: [{ text: 'nfc' }] }),
      'Cafe\u0301.json': j({ entries: [{ text: 'nfd' }, { text: 'nfd2' }] }),
    }, 6),
  },
  { label: 'garbage', zip: b('definitely not a zip') },
  { label: 'only media', zip: zip({ 'photos/a.jpeg': b('x'), 'notes.json': j({ entries: 'no' }) }) },
  { label: 'null json', zip: zip({ 'n.json': b('null') }) },
  { label: 'null entry', zip: zip({ 'a.json': j({ entries: [{ text: 'ok' }, null] }) }) },
  { label: 'number photos', zip: zip({ 'a.json': j({ entries: [{ photos: 5 }] }) }) },
  { label: 'null moment', zip: zip({ 'a.json': j({ entries: [{ photos: [null] }] }) }) },
  { label: 'object videos', zip: zip({ 'a.json': j({ entries: [{ videos: {} }] }) }) },
  { label: 'false audios', zip: zip({ 'a.json': j({ entries: [{ audios: false }] }) }) },
];

const KINDS: [keyof DayOneMomentHolder, MomentKind][] = [['photos', 'image'], ['videos', 'video'], ['audios', 'audio'], ['pdfAttachments', 'file']];
type DayOneMomentHolder = { photos?: unknown; videos?: unknown; audios?: unknown; pdfAttachments?: unknown };
const blobType = (mime: unknown): string => new Blob([], { type: String(mime) }).type;
const sortKey = (a: [string, ...unknown[]], b2: [string, ...unknown[]]) => (a[0] < b2[0] ? -1 : a[0] > b2[0] ? 1 : 0);

function run(z: Uint8Array): unknown {
  let archive;
  try { archive = parseDayOneArchive(z); } catch (e) {
    const m = (e as Error).message;
    return { error: m.startsWith('This file is not a valid .zip') ? 'notZip' : m.startsWith('No Day One journal JSON') ? 'noJournal' : e instanceof TypeError ? 'malformed' : 'other:' + m };
  }
  return {
    journals: archive.journals.map((jr) => ({ name: jr.name, entries: jr.entries.length })),
    entryCount: archive.entryCount, mediaCount: archive.mediaCount,
    entries: archive.journals.flatMap((jr) => jr.entries.map((e) => {
      const resolved: unknown[] = [];
      for (const [key, kind] of KINDS) {
        const arr = (e as DayOneMomentHolder)[key];
        if (!Array.isArray(arr)) continue;
        for (const m of arr) {
          try {
            const r = archive.resolve(m as DayOneMoment, kind);
            resolved.push(r === null ? null : {
              identifier: r.identifier, kind: r.kind, base64: Buffer.from(r.bytes).toString('base64'), mime: blobType(r.mime), name: r.name,
              width: r.width, height: r.height, durationMs: r.durationMs,
            });
          } catch (err) { assert.ok(err instanceof TypeError); resolved.push('throws'); }
        }
      }
      let moments: unknown;
      try {
        moments = [...entryMoments(e).entries()].filter(([k]) => typeof k === 'string')
          .map(([k, v]) => [k, v.kind, JSON.stringify(v.moment)] as [string, string, string]).sort(sortKey);
      } catch (err) { assert.ok(err instanceof TypeError); moments = 'throws'; }
      return { resolved, moments };
    })),
  };
}

export function verifyDayOneArchive(write: boolean): void {
  const fixture = { cases: cases.map((c) => ({ label: c.label, zip: Buffer.from(c.zip).toString('base64'), result: run(c.zip) })) };
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/dayone-archive.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native Day One archive vectors must equal the web importer');
  console.log(`Native Day One archive vectors equal the web importer (${cases.length} archives).`);
}
