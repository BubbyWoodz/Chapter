// SPDX-License-Identifier: AGPL-3.0-or-later
// Writing stats: vectors from the web's own state/stats.ts for the native port.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import * as stats from '../src/state/stats';
import type { JournalEntry } from '../src/sync/engine';

const D = 86_400_000;
const base = Date.UTC(2026, 10, 9, 10, 30); // Mon 9 Nov 2026 10:30 UTC
const raw: [string, number, string][] = [
  ['today', base, 'Hello  world\u00A0again'],
  ['yesterday-late', base - D + 13 * 3600_000 - 1, '\u3000lead and trail\u2028 '],
  ['two-days', base - 2 * D, 'one'],
  ['gap', base - 5 * D, ''],
  ['gap2', base - 6 * D, '  \n\t '],
  ['gap3', base - 7 * D, 'a\uFEFFb c\u200Bd'],
  ['last-year', Date.UTC(2025, 10, 9, 23, 59, 59, 999), 'On this day last year'],
  ['two-years', Date.UTC(2024, 10, 9), 'Two years'],
  ['month-start', Date.UTC(2026, 10, 1), 'x '.repeat(1450)],
  ['oct', Date.UTC(2026, 9, 31, 23, 59), 'October words here'],
  ['epoch-before', -1, 'negative ts'],
];
const entries = raw.map(([id, createdAt, bodyText]) => ({ id, createdAt, bodyText }) as unknown as JournalEntry);
const nows = [base, base + D, base + 2 * D, base - 3 * D, Date.UTC(2026, 10, 15, 23, 0), Date.UTC(2026, 10, 16, 0, 0)];

export function verifyStats(write: boolean): void {
  const words = raw.map(([, , text]) => text).concat(['', ' ', 'a', 'a b', '\u0085x', 'x\u180Ey', '\u2029z']);
  const fixture = {
    entries: raw.map(([id, createdAt, bodyText]) => ({ id, createdAt, bodyText })),
    wordCounts: words.map((text) => ({ text, n: stats.wordCount(text) })),
    totalWords: stats.totalWords(entries), journaledDays: stats.journaledDays(entries), longestStreak: stats.longestStreak(entries),
    streaks: nows.map((now) => ({ now, n: stats.dayStreak(entries, now) })),
    monthWords: [[2026, 10], [2026, 9], [2025, 10], [1969, 11]].map(([y, m]) => ({ year: y, month: m, n: stats.monthWords(entries, y, m) })),
    compact: [0, 999, 1000, 1049, 1050, 1449, 1450, 1951, 1999, 2000, 9950, 10000, 12345, 999949, 999950, 1234567].map((n) => ({ n, out: stats.compactCount(n) })),
    onThisDay: [[10, 9, 2026], [10, 9, 2025], [11, 31, 1970]].map(([m, d, y]) => ({ month: m, day: d, year: y, ids: stats.onThisDay(entries, m, d, y).map((e) => e.id) })),
    daily: nows.map((now) => ({ now, weeks: 3, counts: stats.dailyCounts(entries, now, 3) })),
  };
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/writing-stats.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native stats vectors must equal the web state/stats.ts');
  console.log(`Native writing stats vectors equal the web state/stats.ts (${words.length} word cases, ${nows.length} days).`);
}
