// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of import/run.ts importDayOne: every call it makes on
// the app (notebooks, entries, media, final documents) recorded on a mock, with the clock,
// randomness and time zone pinned.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { zipSync, strToU8 } from 'fflate';
import { parseDayOneArchive } from '../src/import/dayone';
import { importDayOne, type ImportApi } from '../src/import/run';

const mtime = new Date(Date.UTC(2026, 10, 9, 14, 0, 0));
const zip = (files: Record<string, Uint8Array | object>): Uint8Array => zipSync(Object.fromEntries(Object.entries(files).map(([k, v]) =>
  [k, [v instanceof Uint8Array ? v : strToU8(JSON.stringify(v)), { level: 0, mtime }]])));
const b = (s: string): Uint8Array => strToU8(s);
const NOW = 1767225600000, RANDOM = 0.123456, TZ = 'America/Los_Angeles';

const p = (id: string, md5: string, extra: object = {}) => ({ identifier: id, md5, type: 'jpeg', ...extra });
const media = {
  'photos/a1.jpeg': b('img-a1'), 'photos/a2.jpeg': b('img-a2'), 'photos/a3.jpeg': b('img-a3'),
  'videos/v1.mov': b('vid'), 'audios/s1.m4a': b('aud'), 'pdfs/d1.pdf': b('pdf'),
};
const dates = ['2024-05-01T10:00:00Z', '2024-05-01T10:00:00.123456Z', '2024-05-01T10:00:00+02:00', '2024-05-01T10:00:00+0200', '2024-05-01T10:00',
  '2024-05-01', '2024-05', '2024', '+002024-05-01T00:00:00Z', '-000001-01-01T00:00:00Z', '2024-13-01', '2024-02-30', '2024-05-01T24:00:00Z',
  '2024-05-01t10:00:00z', '2024-05-01 10:00:00', 'garbage', '2024-05-01T10:00:00.1Z', '2024-05-01T10:00:60Z', '2024-03-10T02:30:00',
  '2024-11-03T01:30:00', '-000000-01-01T00:00:00Z', '275760-09-13', '2024-05-01T25:00:00Z', '2024-05-01T24:00:01Z', '2024-05-01T24:00Z',
  '2024-05-01T23:59:59.9999Z', '2024-05-01T10:00:00.Z', '2024-05-01T10Z', '2024-05T10:00Z', '2024T10:00Z', '2024-05-01T10:00:00+24:00', '+275760-09-13T00:00:00.001Z', '', null];
const cases: { label: string; zip: Uint8Array; journals: { id: string; name: string }[] }[] = [
  {
    label: 'full', journals: [{ id: 'j-old', name: 'TRAVEL' }, { id: 'j-greek', name: 'ΟΔΟΣ' }, { id: 'j-dup', name: 'work' }, { id: 'j-dup2', name: 'Work' }],
    zip: zip({
      ...media,
      'Travel.json': { entries: [
        { text: '# Lisbon\n\n![](dayone-moment://A1)\n![](dayone-moment://A2)\n![](dayone-moment://A3)\n\nAfter photos ![](dayone-moment://V1)\n![](dayone-moment://A1)\n![](dayone-moment://S1)\n![](dayone-moment://D1)\n![](dayone-moment://NOPE)\n![](dayone-moment:/video/A2)',
          photos: [p('A1', 'a1', { width: 10, height: 20 }), p('A2', 'a2'), p('A3', 'a3', { width: null })],
          videos: [{ identifier: 'V1', md5: 'v1', type: 'mov', duration: 1.5 }], audios: [{ identifier: 'S1', md5: 's1', type: 'm4a', duration: 0.25 }],
          pdfAttachments: [{ identifier: 'D1', md5: 'd1', type: 'pdf' }],
          tags: [' trip ', '', '  ', 3, null, 'lisbon', 'trip'], creationDate: dates[0] },
        ...dates.slice(1).map((d, k) => ({ text: k % 3 ? `Entry ${k}` : '', creationDate: d })),
        { text: '![](dayone-moment://A1)\nCaption', photos: [p('A1', 'a1')] },
        { text: 'Pair\n![](dayone-moment://A2)\n![](dayone-moment://A3)', photos: [p('A2', 'a2'), p('A3', 'a3')] },
        { tags: null }, 5, 'str', [], { text: null, creationDate: 0 },
        { text: '**' + 'Long '.repeat(40) + '**\nbody', creationDate: 1714557600000 },
      ] },
      'Export/οδος.json': { entries: [{ text: 'greek' }] },
      'Work.json': { entries: [] },
      ...Object.fromEntries(Array.from({ length: 9 }, (_, k) => [`N${k}.json`, { entries: [] }])),
      'n3.json': { entries: [{ text: 'same notebook as N3' }] },
    }),
  },
  { label: 'text number', journals: [], zip: zip({ 'a.json': { entries: [{ text: 'ok' }, { text: 5 }] } }) },
  { label: 'tags string', journals: [], zip: zip({ 'a.json': { entries: [{ text: 'ok', tags: 'x' }] } }) },
  { label: 'bad moment', journals: [], zip: zip({ 'photos/5.png': b('x'), 'a.json': { entries: [{ text: '![](dayone-moment://X)', photos: [{ identifier: 'X', md5: 5, type: 'png' }] }] } }) },
];

async function run(c: (typeof cases)[number]): Promise<unknown> {
  const calls: unknown[] = [], progress: unknown[] = [];
  let entries = 0, medias = 0;
  const api: ImportApi = {
    journals: c.journals.map((j) => ({ ...j, subtitle: '', count: 0, color: '', cover: 'plain', last: '' })),
    newJournal: (j) => { calls.push(['newJournal', j.id, j.name, j.subtitle, j.color, j.cover]); },
    createEntry: (i) => { const id = `e${++entries}`; calls.push(['createEntry', i.journalId, i.title ?? null, i.labels]); return { id }; },
    addMedia: async (entryId, kind, blob, meta) => {
      const bytes = Buffer.from(await blob.arrayBuffer());
      calls.push(['addMedia', entryId, kind, blob.type, bytes.toString('base64'), meta?.name, meta?.width, meta?.height, meta?.durationMs]);
      if (kind === 'file') return null;
      return { id: `m${++medias}`, kind, mime: blob.type, bytes: blob.size, name: meta?.name, width: meta?.width, height: meta?.height, durationMs: meta?.durationMs, createdAt: 0 };
    },
    updateEntry: (id, patch) => { calls.push(['updateEntry', id, patch.title ?? null, JSON.parse(patch.bodyJson!), patch.bodyText, patch.labels, patch.createdAt]); },
  };
  try {
    const summary = await importDayOne(parseDayOneArchive(c.zip), api, (pr) => progress.push(pr));
    return { calls, progress, summary };
  } catch (e) { assert.ok(e instanceof TypeError, String(e)); return { calls, progress, error: 'malformed' }; }
}

export async function verifyDayOneImport(write: boolean): Promise<void> {
  const saved = { now: Date.now, random: Math.random, tz: process.env.TZ };
  Date.now = () => NOW; Math.random = () => RANDOM; process.env.TZ = TZ;
  const results: unknown[] = [];
  try { for (const c of cases) results.push({ label: c.label, zip: Buffer.from(c.zip).toString('base64'), journals: c.journals, result: await run(c) }); }
  finally { Date.now = saved.now; Math.random = saved.random; if (saved.tz === undefined) delete process.env.TZ; else process.env.TZ = saved.tz; }
  const fixture = JSON.parse(JSON.stringify({ now: NOW, random: RANDOM, timeZone: TZ, cases: results }));
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/dayone-import.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), fixture, 'Native Day One import vectors must equal the web importer');
  console.log(`Native Day One import vectors equal the web importDayOne (${cases.length} imports, ${dates.length} dates).`);
}
