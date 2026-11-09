// SPDX-License-Identifier: AGPL-3.0-or-later
// Badges: the native app ports state/badges.ts (evaluateBadges, the device-local
// celebrated set and catchUpOrDelta). Vectors come from the real web functions.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import * as badges from '../src/state/badges';
import { BUILTIN_INTERVIEWS } from '../src/data/interviews';
import type { JournalEntry } from '../src/sync/engine';

const DAY = 86_400_000, T0 = Date.UTC(2026, 0, 10, 15);
const words = (n: number) => Array.from({ length: n }, (_, i) => 'w' + i).join(' ');
const doc = (...content: unknown[]) => JSON.stringify({ type: 'doc', content });
const e = (id: string, over: Partial<JournalEntry> = {}): JournalEntry => ({ id, journalId: 'j', title: '', bodyText: 'hello', labels: [], createdAt: T0, updatedAt: T0, deleted: false, ...over } as JournalEntry);
const seed = [...badges.SEED_ENTRY_IDS];
const sets: { name: string; entries: JournalEntry[]; types: string[] }[] = [
  { name: 'empty', entries: [], types: [] },
  { name: 'seed-only', entries: seed.map((id, i) => e(id, { createdAt: T0 + i * DAY, bodyText: words(1200), attachments: [{ id: 'x' }] as never })), types: [] },
  { name: 'one', entries: [e('u1')], types: [] },
  { name: 'deleted-only', entries: [e('u1', { deleted: true })], types: [] },
  { name: 'streak-3', entries: [0, 1, 2].map((d) => e('s' + d, { createdAt: T0 + d * DAY })), types: [] },
  { name: 'streak-gap', entries: [0, 1, 3, 4].map((d) => e('g' + d, { createdAt: T0 + d * DAY })), types: [] },
  { name: 'streak-7', entries: [0, 1, 2, 3, 4, 5, 6].map((d) => e('w' + d, { createdAt: T0 + d * DAY - (d % 2) * 14 * 3600_000 })), types: [] },
  { name: 'deep-dive', entries: [e('d', { bodyText: words(1000) })], types: [] },
  { name: 'wordsmith-split', entries: [e('a', { bodyText: words(600) }), e('b', { bodyText: '  ' + words(400) + '\n' })], types: [] },
  { name: 'almost', entries: [e('a', { bodyText: words(999) })], types: [] },
  { name: 'interview', entries: [e('i', { labels: ['travel', 'Daily check-in'] })], types: ['Daily check-in', 'Dream log'] },
  { name: 'interview-miss', entries: [e('i', { labels: ['daily check-in'] })], types: ['Daily check-in'] },
  { name: 'on-camera', entries: [e('v', { bodyJson: doc({ type: 'paragraph' }, { type: 'videoInterview', attrs: { cards: [{ clip: { id: 'c1' } }] } }) })], types: [] },
  { name: 'camera-mention', entries: [e('v', { bodyJson: doc({ type: 'paragraph', attrs: { note: 'videoInterview' }, content: [{ type: 'text', text: 'my "videoInterview" idea' }] }) })], types: [] },
  { name: 'video-no-media', entries: [e('v', { bodyJson: doc({ type: 'videoInterview', attrs: { cards: [] } }) })], types: [] },
  { name: 'gallery', entries: [e('m', { bodyJson: doc({ type: 'mediaGallery', attrs: { images: [{ id: '' }, { id: 'img1' }] } }) })], types: [] },
  { name: 'attachment-empty-id', entries: [e('m', { bodyJson: doc({ type: 'mediaAttachment', attrs: { id: '' } }) })], types: [] },
  { name: 'map-without-ids', entries: [e('m', { bodyJson: doc({ type: 'locationMap', attrs: { map: {}, photo: null } }) })], types: [] },
  { name: 'map-photo', entries: [e('m', { bodyJson: doc({ type: 'blockquote', content: [{ type: 'locationMap', attrs: { photo: { id: 'p' } } }] }) })], types: [] },
  { name: 'legacy-attachments', entries: [e('m', { attachments: [{ id: 'a1', kind: 'audio' }] as never })], types: [] },
  { name: 'invalid-json', entries: [e('m', { bodyJson: '{"type":"mediaAttachment","attrs":{"id":"x"}' })], types: [] },
  { name: 'deleted-media', entries: [e('m', { deleted: true, attachments: [{ id: 'a1' }] as never }), e('ok')], types: [] },
];
const seenRaw = [null, '[]', '["first-words","bogus","streak-7"]', '{}', 'not json', '"x"', '["streak-7","first-words","first-words"]'];
const earnedSets = [[], ['first-words'], ['memory-keeper', 'first-words', 'streak-3']];

export function verifyBadges(write: boolean): void {
  const store = (raw: string | null) => ({ getItem: () => raw, setItem: () => undefined });
  const fixture = {
    order: badges.BADGE_ORDER,
    seedEntryIds: seed,
    interviews: BUILTIN_INTERVIEWS.map((b) => ({ slug: b.slug, nameKey: b.nameKey })),
    seenKey: badges.seenKey('OWNER'),
    evaluate: sets.map((s) => ({ name: s.name, types: s.types, entries: s.entries, earned: badges.BADGE_ORDER.filter((id) => badges.evaluateBadges(s.entries, s.types).has(id)) })),
    seen: seenRaw.map((raw) => { const v = badges.loadSeen(store(raw), 'OWNER'); return { raw, seen: v === null ? null : [...v] }; }),
    delta: seenRaw.flatMap((raw) => earnedSets.map((earned) => { const seen = badges.loadSeen(store(raw), 'OWNER'); const r = badges.catchUpOrDelta(seen, new Set(earned as badges.BadgeId[])); return { raw, earned, seen: [...r.seen], celebrate: r.celebrate }; })),
  };
  const resURL = new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/badges.json', import.meta.url);
  const vecURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/badges.json', import.meta.url);
  const resource = { order: fixture.order, seedEntryIds: fixture.seedEntryIds, interviews: fixture.interviews };
  if (write) { writeFileSync(resURL, JSON.stringify(resource) + '\n'); writeFileSync(vecURL, JSON.stringify(fixture, null, 1) + '\n'); }
  else {
    assert.deepEqual(JSON.parse(readFileSync(resURL, 'utf8')), resource, 'Native badge data must equal the web');
    assert.deepEqual(JSON.parse(readFileSync(vecURL, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native badge vectors must equal the web state/badges.ts');
  }
  console.log(`Native badge vectors equal the web state/badges.ts (${sets.length} vaults, ${fixture.delta.length} catch-up cases).`);
}
