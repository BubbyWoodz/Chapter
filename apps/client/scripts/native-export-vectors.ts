// SPDX-License-Identifier: AGPL-3.0-or-later
// Journal export: the native app ports export/journal.ts + export/collect.ts (the
// public mneme-journal-export v1 archive). Vectors come from the real web
// exportJournal; the native archive is unzipped here and compared file by file.
import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { unzipSync, strFromU8 } from 'fflate';
import { exportJournal, slugify } from '../src/export/journal';
import type { JournalEntry } from '../src/sync/engine';
import type { Journal } from '../src/data/sample';

// Media dates are real ones. Undated media (an out-of-zip-range mtime) is covered by
// scripts/export-journal.ts checkUndatedMedia, and zip mtimes aren't compared here.
const NOW = Date.UTC(2026, 10, 9, 13, 20, 0, 123);
const doc = (...content: unknown[]) => JSON.stringify({ type: 'doc', content });
const p = (text: string) => ({ type: 'paragraph', content: [{ type: 'text', text }] });
const journal = { id: 'public-notebook', name: 'Café Notes — été 2026', subtitle: 'Public', color: '#B0563A', cover: 'grid', count: 0, last: '', createdAt: 1700000000000, updatedAt: 1700000005000 } as Journal & { createdAt: number; updatedAt: number };
const entries = [
  { id: 'e2-newer', journalId: 'public-notebook', title: 'Second', bodyText: 'Second body', labels: ['b'], createdAt: 1700000200000, updatedAt: 1700000300000, deleted: false,
    bodyJson: doc(p('Links to first'), { type: 'paragraph', content: [{ type: 'entryLink', attrs: { entryId: 'e1/old!', label: 'First' } }, { type: 'entryLink', attrs: { entryId: '' } }] },
      { type: 'mediaAttachment', attrs: { id: 'shared01', kind: 'image', mime: 'image/png', name: 'pic.png', bytes: 3, createdAt: 1700000100000, width: 2, height: 1 } },
      { type: 'mediaAttachment', attrs: { id: 'missing02', kind: 'audio', mime: 'audio/webm;codecs=opus', bytes: 9, createdAt: 'x' } }) },
  { id: 'e1/old!', journalId: 'public-notebook', title: 'First', bodyText: 'First body', labels: [], createdAt: 1700000100000, updatedAt: 1700000100000, deleted: false,
    bodyJson: doc(p('Hello'), { type: 'mediaGallery', attrs: { images: [{ id: 'shared01', mime: 'image/png', name: '', createdAt: 1650000000000 }, { id: '' }, { id: 'gal/../02', mime: 'image/heic', createdAt: 1650000000001 }] } },
      { type: 'blockquote', content: [{ type: 'locationMap', attrs: { map: { id: 'map03', mime: 'image/png', createdAt: 1650000000002 }, photo: null } }] },
      { type: 'videoInterview', attrs: { cards: [{ clip: { id: 'clip04', kind: 'video', mime: 'video/mp4', durationMs: 1500, createdAt: 1650000000003 } }, { clip: null }, 'x'], film: { id: 'film05', mime: 'video/quicktime', name: 'film.MOV', createdAt: 1650000000004 } } }),
    attachments: [{ id: 'legacy06', kind: 'file', mime: 'application/x-unknown', name: 'notes.TAR', bytes: 4, createdAt: 1600000000000 }, { id: 'clip04', kind: 'video', mime: 'video/mp4' }, { id: '' }] },
  { id: 'e3', journalId: 'public-notebook', title: 'Malformed', bodyText: 'line one\n\nline three', labels: ['x', 'y'], createdAt: 1700000150000, updatedAt: 1700000150000, deleted: false, bodyJson: '{not json' },
  { id: 'e4', journalId: 'public-notebook', title: 'Number body', bodyText: 'n', labels: [], createdAt: 1700000160000, updatedAt: 1700000160000, deleted: false, bodyJson: '42' },
  { id: 'e5', journalId: 'public-notebook', title: 'CRLF text', bodyText: 'windows\r\nline *two*\r\n', labels: [], createdAt: 1700000170000, updatedAt: 1700000170000, deleted: false },
  { id: 'e6', journalId: 'public-notebook', title: 'Serializer throws', bodyText: 'fallback text', labels: [], createdAt: 1700000180000, updatedAt: 1700000180000, deleted: false, bodyJson: '{"type":"doc","content":[null]}' },
  { id: 'e7', journalId: 'public-notebook', title: 'Key order', bodyText: '', labels: [], createdAt: 1700000190000, updatedAt: 1700000190000, deleted: false, bodyJson: '{"content":[{"attrs":{"z":1,"1":2,"id":"x9","mime":"text/plain"},"type":"mediaAttachment"},{"type":"paragraph","content":[{"type":"text","text":"*hi*","marks":[{"type":"link","attrs":{"href":"https://e.com"}}]}]}],"type":"doc"}' },
  { id: 'gone', journalId: 'public-notebook', title: 'Deleted', bodyText: 'x', labels: [], createdAt: 1700000000000, updatedAt: 1700000000000, deleted: true },
  { id: 'other', journalId: 'elsewhere', title: 'Other notebook', bodyText: 'x', labels: [], createdAt: 1700000000000, updatedAt: 1700000000000, deleted: false },
] as unknown as JournalEntry[];
const available: Record<string, number[]> = { shared01: [1, 2, 3], map03: [9, 8, 7, 6], clip04: [0, 255], film05: [5], legacy06: [4, 4, 4, 4], x9: [7], 'gal/../02': [2] };

type Files = Record<string, unknown>;
function readArchive(zip: Uint8Array): Files {
  const files: Files = {};
  for (const [path, data] of Object.entries(unzipSync(zip))) {
    if (path.endsWith('.json')) { const v = JSON.parse(strFromU8(data)) as Record<string, unknown>; files[path] = v; }
    else if (path.endsWith('.md')) files[path] = strFromU8(data);
    else files[path] = Buffer.from(data).toString('base64');
  }
  return files;
}

export async function verifyExport(write: boolean): Promise<void> {
  const progress: { done: number; total: number; current: string }[] = [];
  const result = await exportJournal('public-notebook', { journals: [journal], entries, mediaBlob: async (_e: string, att: { id: string }) => (available[att.id] ? new Blob([new Uint8Array(available[att.id])]) : null) } as never, (p) => progress.push({ ...p }), { now: () => NOW, appVersion: 'test' });
  const zip = new Uint8Array(await result.blob.arrayBuffer());
  const files = readArchive(zip);
  const slugs = ['Café Notes — été 2026', '日本語', '  --Hello__World--  ', 'x'.repeat(80), 'Ǆemal ﬁle'].map((name) => ({ name, slug: slugify(name) }));
  const fixture = { now: NOW, journal, entries, available, filename: result.filename, files, slugs, progress };
  const vecURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/journal-export.json', import.meta.url);
  if (write) writeFileSync(vecURL, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(vecURL, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native export vectors must equal the web exportJournal');
  const out = process.env.CHAPTER_NATIVE_OUTPUT;
  if (out && existsSync(out + '.journal-export.zip')) {
    const native = readArchive(new Uint8Array(readFileSync(out + '.journal-export.zip')));
    assert.deepEqual(native, JSON.parse(JSON.stringify(files)), 'The native archive must unzip to the same files as the web export');
    console.log('Swift journal export → fflate unzip: every file equals the web exportJournal, markdown included.');
  }
  console.log(`Native export vectors equal the web exportJournal (${Object.keys(files).length} files).`);
}
