// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of video/timeline.ts and editor/videointerviewData.ts
// (coercion, answered/stale rules, and the out-of-editor transcript/film write-back), run on the
// real web functions, including JavaScript's loose edge cases (Number(), spread, NaN in Math.max).
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { planTimeline, estimateSeconds, canonicalSize, containFit, filmBitrate, CARD_SECONDS, FILM_FPS } from '../src/video/timeline';
import {
  coerceVideoInterview, isAnswered, videoInterviewAttachments, isFilmStale, setTranscriptAttr, setFilmAttr,
} from '../src/editor/videointerviewData';
import type { MediaAttachment } from '../src/sync/engine';

// Non-finite numbers and -0 survive JSON as {"$num": "..."}.
const enc = (_k: string, v: unknown): unknown =>
  typeof v === 'number' && (!Number.isFinite(v) || Object.is(v, -0)) ? { $num: Object.is(v, -0) ? '-0' : String(v) } : v;
const tryIt = <T>(f: () => T): T | { throws: true } => { try { return f(); } catch (err) { assert.ok(err instanceof TypeError, String(err)); return { throws: true }; } };

const timelines: [number[], number, number][] = [
  [[], FILM_FPS, CARD_SECONDS], [[4.2, 10, 0.5], FILM_FPS, CARD_SECONDS], [[0, 0.01, -3], 30, 2.5],
  [[1 / 3, 2 / 3, 59.99, 0.0166], 24, 2.5], [[12.345, 7.777], 60, 0], [[5], 30, 0.0001], [[NaN, 2], 30, 2.5],
  [[Infinity], 30, 2.5], [[2.5], NaN, 2.5], [[2.5], 30, -1], [[0.016666666666666666, 0.05, 0.0499], 30, 1 / 60],
  [[600, 1800.5, 3599.98, 0.75, 33.3, 44.4], 30, 2.5], [[1.5, 2.5, -0.5, -1.5], 1, 2.5], [[1e-9], 29.97, 2.5],
];
const sizes: [number, number][] = [
  [1920, 1080], [1080, 1920], [720, 720], [640, 480], [480, 640], [4000, 100], [100, 4000], [641, 481], [1281, 721],
  [0, 0], [5, 0], [0, 5], [-1920, 1080], [1920, -1080], [NaN, 100], [3, 2], [2, 3], [1080.5, 1920.25], [1e9, 1], [1, 1e9],
];

// Source frames contain-fitted into canonical boxes (worker and realtime paths), including the
// missing-dimension fallback (0, -0, NaN) and the half-pixel rounding of the centring offsets.
const boxes: [number, number][] = [[1280, 720], [720, 1280], [720, 720], [640, 720], [1278, 720], [2, 2], [641, 361], [720, 0]];
const sources: [number, number][] = [
  [1920, 1080], [1080, 1920], [1280, 720], [720, 1280], [640, 480], [481, 641], [4000, 100], [100, 4000], [1, 1], [3, 1], [1, 3],
  [0, 0], [0, 1080], [1920, 0], [-0, 5], [NaN, 720], [720, NaN], [-1920, 1080], [1920, -1080], [Infinity, 720], [1e-9, 1], [1279, 721], [1281, 719], [1, -2], [-2, 1],
];
const fits = boxes.flatMap(([bw, bh]) => sources.map(([sw, sh]) => [sw, sh, bw, bh] as [number, number, number, number]));
const bitrates: [number, number, number | undefined][] = [
  [1280, 720, undefined], [720, 1280, undefined], [720, 720, undefined], [640, 720, undefined], [2, 2, undefined], [1280, 720, 60],
  [1280, 720, 24], [1920, 1080, 30], [0, 0, 30], [NaN, 720, 30], [1280, 720, NaN], [10000, 10000, 30], [400, 400, 30], [585, 633, 30], [1280.5, 720, 30], [1001, 601, 30],
];

const clip = (o: Record<string, unknown> = {}): Record<string, unknown> => ({ id: 'c1', kind: 'video', mime: 'video/mp4', bytes: 1200, durationMs: 4200, width: 1080, height: 1920, createdAt: 1767225600000, ...o });
const numbers: unknown[] = ['12', ' 12 ', '', '   ', '0x1F', '0X1f', '0b101', '0B11', '0o17', '0O7', '0x', '0b2', '0o8', '1e3', '.5', '5.', '+5', '-5', '+.5e1',
  '-0', '1.5e+3', '1E-2', 'Infinity', '-Infinity', '+Infinity', 'infinity', 'inf', 'nan', 'NaN', '1_000', '1e', '12px', '--1', '+0x1', '-0x1',
  '\u00a012\ufeff', '\u2028 7 \u3000', '\u0661\u0662', '00012', '0.0000001', '123456789012345678901234567890', '0x1fffffffffffff', '0x20000000000001',
  '0xfffffffffffffffffffffff', '0b' + '1'.repeat(70), '0o' + '7'.repeat(30), '1e400', '-1e400', '5e-400', '0x1p3', '1,5', ' \t\n\r\v\f8',
  true, false, [], [7], ['8'], [1, 2], [[[3]]], [null], {}, { a: 1 }, 0, -0, 3.25, null];
const mimes: unknown[] = [undefined, null, 'video/quicktime', '', 5, 1e21, true, [], ['a', null, ['b', 'c']], { x: 1 }, 0.1];

const attrsCases: unknown[] = [
  { sessionId: 's1', typeName: 'Origin story', cards: [{ q: 'Where did you grow up?', clip: clip(), transcript: 'In Lisbon.' }, { q: 'Q2', clip: null }], film: clip({ id: 'f1', createdAt: 1767225700000 }), renderedAt: 1767225650000, lang: 'pt' },
  { cards: [] }, { cards: {} }, { cards: 'abc' }, {}, 'str', 5, [], { cards: [null, 3, 'x', [], [1], true, {}] },
  { sessionId: 7, typeName: ['a'], cards: [{ q: 5, transcript: '', dropped: 'true' }, { q: 'kept', dropped: true }, { transcript: 'only words' }], renderedAt: '5', lang: '' },
  { cards: [{ clip: { id: '' } }, { clip: { id: 5 } }, { clip: [] }, { clip: 'c' }, { clip: { id: 'x' } }, { clip: { id: 'y', name: '', durationMs: '5', width: null, height: 2.5, createdAt: null } }] },
  { cards: [{ clip: clip({ createdAt: 10 }) }, { clip: clip({ id: 'c2', createdAt: 30 }) }], film: clip({ id: 'f' }), renderedAt: 20 },
  { cards: [{ clip: clip({ createdAt: 10 }) }], film: clip({ id: 'f' }), renderedAt: 10 },
  { cards: [{ clip: clip({ createdAt: 'later' }) }], film: clip({ id: 'f' }), renderedAt: 0 },
  { cards: [{ clip: clip() }], film: null, renderedAt: 0 }, { cards: [{ clip: clip() }], film: clip({ id: 'f' }), renderedAt: null },
  { cards: [{ clip: clip(), dropped: true }], film: { id: 'f2', kind: 'audio', mime: 'audio/mp4', extra: 1 } },
  ...numbers.map((n) => ({ cards: [{ clip: clip({ bytes: n, createdAt: n }) }] })),
  ...mimes.map((m) => ({ cards: [{ clip: m === undefined ? { id: 'm' } : { id: 'm', mime: m } }] })),
  { cards: [{ clip: { id: 'n', bytes: undefined, mime: null, createdAt: undefined } }] },
];
// `attrs.cards` on null throws, as it does in the web.
const coerceCases = [...attrsCases.map((a) => JSON.parse(JSON.stringify(a)) as unknown), null];

const vi = (sessionId: unknown, cards: unknown, extra: Record<string, unknown> = {}): Record<string, unknown> =>
  ({ type: 'videoInterview', attrs: { sessionId, typeName: 'T', cards, film: null, renderedAt: null, ...extra } });
const doc = (...content: unknown[]): string => JSON.stringify({ type: 'doc', content: [...content, { type: 'paragraph' }] });
const cards = [{ q: 'Q1', clip: clip() }, { q: 'Q2', clip: null, transcript: 'old', z: 1 }, 'ab', 5, null, [1, 2], { 1: 'x', q: 'idx' }, true];
const bodies: (string | undefined)[] = [
  doc(vi('s1', cards)), doc({ type: 'blockquote', content: [vi('s1', cards)] }), doc(vi('s1', cards), vi('s1', [{ q: 'B' }]), vi('s2', [{ q: 'C' }])),
  undefined, '', '{bad', 'null', '5', '"str"', '[]', 'true',
  JSON.stringify({ type: 'doc', content: 'x' }), JSON.stringify({ type: 'doc', content: { a: 1 } }), JSON.stringify({ type: 'doc', content: null }),
  JSON.stringify({ type: 'doc', content: [5, 'str', true, [], vi('s1', [{ q: 'A' }])] }), JSON.stringify({ type: 'doc', content: [vi('s1', [{ q: 'A' }]), null] }),
  JSON.stringify({ type: 'doc', content: [{ type: 'videoInterview', attrs: null }, { type: 'videoInterview' }, { type: 'videoInterview', attrs: 'x' }] }),
  doc(vi('', [{ q: 'empty session id' }])),
  doc(vi('s1', 'notarray')), doc(vi('s1', null)), doc({ type: 'videoInterview', attrs: { sessionId: 's1' } }),
  '{"type":"doc","content":[{"type":"x","attrs":{"sessionId":"s1","cards":[{"q":"d","q":"dup"}],"sessionId":"s1"},"type":"videoInterview"}]}',
  '{"type":"doc","content":[{"type":"videoInterview","attrs":{"sessionId":"s1","cards":[{"q":"n","n":[1e21,0.1,-0,5e-7,123456789.125,1e-7,-1.5e300]}],"2":"two","10":"ten","b":1}}]}',
  ' \n{"type":"doc","content":[{"type":"videoInterview","content":[{"type":"videoInterview","attrs":{"sessionId":"s1","cards":[{}]}}],"attrs":{"sessionId":"s1","cards":[{"q":"Olá — 日本 \\u00e9\\n\\"q\\""}]}}]}\t',
];
const transcriptCalls: [number, string, number, string][] = [];
bodies.forEach((_, b) => {
  for (const [s, i] of [['s1', 0], ['s1', 1], ['s1', 2], ['s1', 3], ['s1', 4], ['s1', 5], ['s1', 6], ['s1', 7], ['s1', 8], ['s1', -1], ['s2', 0], ['', 0], ['nope', 0]] as [string, number][])
    transcriptCalls.push([b, s, i, i % 2 ? 'Olá — "quoted" 😀 line\nbreak' : 'Plain words.']);
});
const films: Record<string, unknown>[] = [clip({ id: 'film-1', name: 'Film.mp4' }), { id: 'f2', kind: 'video', mime: 'video/webm', bytes: 0, createdAt: 0 }];
const filmCalls: [number, string, number, number][] = [];
bodies.forEach((_, b) => { for (const [s, f, at] of [['s1', 0, 1767225600000], ['s1', 1, 1.5], ['s2', 0, -0], ['', 0, 1], ['nope', 1, 2]] as [string, number, number][]) filmCalls.push([b, s, f, at]); });

function build(): unknown {
  return {
    constants: { cardSeconds: CARD_SECONDS, fps: FILM_FPS },
    timelines: timelines.map(([d, fps, card]) => ({ durations: d, fps, card, out: planTimeline(d, fps, card), estimate: estimateSeconds(d, card) })),
    sizes: sizes.map(([w, h]) => ({ w, h, out: canonicalSize(w, h) })),
    fits: fits.map(([sw, sh, w, h]) => ({ sw, sh, w, h, out: containFit(sw, sh, w, h) })),
    bitrates: bitrates.map(([w, h, fps]) => ({ w, h, fps: fps ?? null, out: fps === undefined ? filmBitrate(w, h) : filmBitrate(w, h, fps) })),
    coerce: coerceCases.map((attrs) => {
      const out = tryIt(() => coerceVideoInterview(attrs as Record<string, unknown>));
      const derived = out && !('throws' in out)
        ? { answered: out.cards.map(isAnswered), attachments: videoInterviewAttachments(out).map((a) => a.id), stale: isFilmStale(out) } : null;
      return { attrs, out, derived };
    }),
    bodies,
    transcripts: transcriptCalls.map(([b, s, i, t]) => ({ body: b, sessionId: s, index: i, transcript: t, out: tryIt(() => setTranscriptAttr(bodies[b], s, i, t)) })),
    films,
    filmWrites: filmCalls.map(([b, s, f, at]) => ({ body: b, sessionId: s, film: f, at, out: tryIt(() => setFilmAttr(bodies[b], s, films[f] as unknown as MediaAttachment, at)) })),
  };
}

export function verifyVideo(write: boolean): void {
  const fixture = JSON.parse(JSON.stringify(build(), enc)) as unknown;
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/video-interview.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), fixture, 'Native video vectors must equal the web video/timeline and video-interview data code');
  console.log(`Native video vectors equal the web (${timelines.length} timelines, ${sizes.length} sizes, ${fits.length} fits, ${bitrates.length} bitrates, ${coerceCases.length} sessions, ${transcriptCalls.length + filmCalls.length} write-backs).`);
}
