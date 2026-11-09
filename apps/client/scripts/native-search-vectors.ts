// SPDX-License-Identifier: AGPL-3.0-or-later
// Vault search: the native app ports search/core.ts and the Search sheet's
// searchHits (month-translated union, empty-query recents). Vite SSR loads the
// real modules; month names come from the web monthName() in every locale.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'vite';
import type { JournalEntry } from '../src/sync/engine';

const TZ = 'America/Los_Angeles';
const day = (y: number, m: number, d: number, h = 12, min = 0) => Date.UTC(y, m - 1, d, h + 7, min); // ~PDT/PST noon-ish
const long = 'Morning walk through the garden. '.repeat(4) + 'The rain started 🌧️ near the old bridge and we sheltered under the oak. ' + 'Later the sun returned. '.repeat(3);
const base: Partial<JournalEntry>[] = [
  { id: 'a', title: 'Garden walk', labels: ['nature', 'travel'], bodyText: long, createdAt: day(2026, 6, 9), updatedAt: day(2026, 6, 10) },
  { id: 'b', title: 'Rainy café', labels: ['coffee'], bodyText: 'Über die Brücke, then café au lait. Garden later?', createdAt: day(2026, 3, 1), updatedAt: day(2026, 3, 2) },
  { id: 'c', title: '', labels: [], bodyText: 'Untitled thoughts about the travel plan', createdAt: day(2025, 12, 31, 23, 30), updatedAt: day(2026, 1, 1) },
  { id: 'd', title: 'ΟΔΟΣ notes', labels: ['greek'], bodyText: 'Η ΟΔΟΣ ήταν μακριά', createdAt: day(2026, 11, 1), updatedAt: day(2026, 11, 2) },
  { id: 'e', title: 'Deleted garden', labels: [], bodyText: 'gone', createdAt: day(2026, 6, 9), updatedAt: day(2026, 6, 11), deleted: true },
  { id: 'f', title: 'Mai Tagebuch', labels: ['de'], bodyText: 'Ein Tag im Mai\twith   tabs\nand lines', createdAt: day(2026, 5, 4), updatedAt: day(2026, 6, 10) },
  { id: 'g', title: 'June plans', labels: ['plans'], bodyText: 'Planning for june', createdAt: day(2026, 1, 15), updatedAt: day(2026, 1, 15) },
];
const many: Partial<JournalEntry>[] = Array.from({ length: 56 }, (_, i) => ({ id: 'm' + String(i).padStart(2, '0'), title: 'Note ' + i, labels: [], bodyText: 'common ground ' + i, createdAt: day(2024, 1 + (i % 12), 1 + (i % 27)), updatedAt: 1700000000000 + (i % 5) }));
const entries = [...base, ...many].map((e) => ({ journalId: 'j', bodyJson: '', ...e, deleted: e.deleted ?? false })) as JournalEntry[];
const queries = ['garden', '  Garden   WALK ', 'jun 9', '9 june', 'june 9 2026', '2026-06-09', '9.6.2026', '09.06.2026', '06/09/2026', 'mar 1', 'travel', 'nature garden', 'rain', 'bridge oak', 'über', 'ÜBER', 'café', 'οδος', 'οδοσ', 'ΟΔΟΣ', 'common', 'note 5', 'xyz', '', '   ', 'dec 31 2025', 'jan 1 2026', 'mai', 'tabs and', 'th', '🌧️', 'later'];

export async function verifySearch(write: boolean): Promise<void> {
  const previousTZ = process.env.TZ;
  process.env.TZ = TZ;
  const vite = await createServer({ configFile: false, root: new URL('..', import.meta.url).pathname, logLevel: 'error', server: { middlewareMode: true, hmr: false, ws: false }, appType: 'custom', optimizeDeps: { noDiscovery: true, include: [] } });
  try {
    const i18n = (await vite.ssrLoadModule('/src/i18n/index.tsx')) as typeof import('../src/i18n');
    const ui = (await vite.ssrLoadModule('/src/ui/Search.tsx')) as typeof import('../src/ui/Search');
    const months: Record<string, { long: string[]; short: string[] }> = {};
    const vectors: Record<string, unknown> = {};
    for (const info of i18n.LOCALES) {
      await i18n.setLocale(info.id);
      months[info.id] = { long: Array.from({ length: 12 }, (_, m) => i18n.monthName(m, 'long')), short: Array.from({ length: 12 }, (_, m) => i18n.monthName(m, 'short')) };
      const local = [...queries, ...[5, 2].flatMap((m) => [months[info.id].long[m].toLowerCase() + ' 9', '9 ' + months[info.id].short[m].toLowerCase(), months[info.id].short[m].toLowerCase().slice(0, 3)])];
      vectors[info.id] = local.map((q) => ({ q, english: ui.toEnglishMonths(q.trim().toLowerCase().replace(/\s+/g, ' ')), hits: ui.searchHits(entries, q).map((h) => ({ id: h.entry.id, field: h.field, snippet: h.snippet ?? null })) }));
    }
    await i18n.setLocale('en');
    const monthsURL = new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/search-months.json', import.meta.url);
    const vectorURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/search.json', import.meta.url);
    const fixture = { timeZone: TZ, entries: entries.map(({ id, title, labels, bodyText, createdAt, updatedAt, deleted }) => ({ id, title, labels, bodyText, createdAt, updatedAt, deleted })), vectors };
    if (write) { writeFileSync(monthsURL, JSON.stringify(months) + '\n'); writeFileSync(vectorURL, JSON.stringify(fixture, null, 1) + '\n'); }
    else {
      assert.deepEqual(JSON.parse(readFileSync(monthsURL, 'utf8')), months, 'Native month names must equal the web monthName()');
      assert.deepEqual(JSON.parse(readFileSync(vectorURL, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native search vectors must equal the web searchHits');
    }
    const n = Object.values(vectors).reduce((a: number, v) => a + (v as unknown[]).length, 0);
    console.log(`Native search vectors equal the web search/core and Search sheet (${n} queries in ${i18n.LOCALES.length} locales).`);
  } finally {
    await vite.close();
    if (previousTZ === undefined) delete process.env.TZ; else process.env.TZ = previousTZ;
  }
}
