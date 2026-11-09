// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of video/audiomix.ts (Float32 downmix, linear resample, silence,
// fit, chunking) and the pure parts of ui/recorder.ts (quality table, MB per minute, stored-value
// parsing, the M:SS clock and countdown), run on the real web functions.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { downmixToMono, resampleLinear, silence, fitLength, chunkFrames } from '../src/video/audiomix';

const store = new Map<string, string>();
(globalThis as { localStorage?: unknown }).localStorage = {
  getItem: (k: string) => (store.has(k) ? store.get(k)! : null), setItem: (k: string, v: string) => void store.set(k, String(v)),
  removeItem: (k: string) => void store.delete(k),
};
const rec = await import('../src/ui/recorder');

const enc = (_k: string, v: unknown): unknown =>
  typeof v === 'number' && (!Number.isFinite(v) || Object.is(v, -0)) ? { $num: Object.is(v, -0) ? '-0' : String(v) } : v;
const f32 = (a: number[]): Float32Array => Float32Array.from(a);
const wave = (n: number, k: number): number[] => Array.from({ length: n }, (_, i) => Math.fround(Math.sin(i * k) * 0.8 + (i % 7) / 97));

const downmixes: number[][][] = [[], [[0.5, -0.25]], [[1, 0.5, 0], [0, 0.5, 1]], [[0.1, 0.2, 0.3], [0.7]], [wave(64, 0.3), wave(64, 0.71), wave(64, 1.9)],
  [[1e-45, 3.4028234663852886e38], [1e-45, 3.4028234663852886e38]], [[0.3333333432674408, 0.1], [0.6666666865348816, 0.2], [0.1, 0.30000001192092896]]];
const resamples: [number[], number, number][] = [[[], 44100, 48000], [[0.5], 44100, 48000], [[0.5], 48000, 44100], [wave(441, 0.05), 44100, 48000],
  [wave(480, 0.05), 48000, 44100], [wave(100, 0.4), 16000, 48000], [wave(97, 0.9), 48000, 8000], [wave(10, 1), 48000, 48000], [[1, -1, 1, -1], 3, 7], [[0.25, 0.75], 1, 1000], [wave(5, 2), 1000, 1]];
const fits: [number[], number][] = [[[], 0], [[], 3], [[0.5, 0.25], 2], [[0.5, 0.25, 0.125], 1], [[0.5], 4], [wave(9, 0.2), 0], [wave(9, 0.2), 12]];
const chunks: [number, number][] = [[0, 1024], [-5, 1024], [1, 1024], [1024, 1024], [1025, 1024], [48000 * 2.5, 1024], [10, 3], [7, 7], [7, 100]];
const durations = [0, 499, 500, 501, 999.9, 1000, 59499, 59500, 60000, 61234, 599999, 3600000, 3599500, 36000000, -1, -499, -500, -501, -1500, -60000, -61000, 0.5, NaN, Infinity, -Infinity, 1e21, -0];
const stored = [null, '', '15', '14.99', '600', '600.5', '45.5', '90', ' 120 ', '0x3c', '1e2', 'abc', 'Infinity', '-30', '300', '7', '601'];

function build(): unknown {
  return {
    downmix: downmixes.map((p) => ({ planes: p, out: Array.from(downmixToMono(p.map(f32))) })),
    resample: resamples.map(([s, a, b]) => ({ src: s.map(Math.fround), from: a, to: b, out: Array.from(resampleLinear(f32(s), a, b)) })),
    silence: [0, 1, 7, -3].map((n) => ({ frames: n, out: silence(n).length })),
    fit: fits.map(([d, n]) => ({ data: d.map(Math.fround), frames: n, out: Array.from(fitLength(f32(d), n)) })),
    chunks: chunks.map(([t, p]) => ({ total: t, per: p, out: chunkFrames(t, p) })),
    quality: { table: rec.VIDEO_QUALITY, mbPerMinute: { low: rec.megabytesPerMinute('low'), medium: rec.megabytesPerMinute('medium'), high: rec.megabytesPerMinute('high') },
      stored: [null, 'low', 'medium', 'high', 'HIGH', '', 'ultra'].map((v) => { store.clear(); if (v !== null) store.set('mneme.video.quality', v); return { stored: v, out: rec.videoQuality() }; }) },
    answerLimits: { presets: rec.ANSWER_LIMITS, stored: stored.map((v) => { store.clear(); if (v !== null) store.set('mneme.videoInterview.maxSeconds', v); return { stored: v, out: rec.answerLimitSeconds() }; }) },
    clock: durations.map((ms) => ({ ms, duration: rec.fmtDuration(ms), countdown: rec.fmtCountdown(ms) })),
  };
}

export function verifyAudio(write: boolean): void {
  const fixture = JSON.parse(JSON.stringify(build(), enc)) as unknown;
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/audio-recorder.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), fixture, 'Native audio/recorder vectors must equal the web audiomix.ts and recorder.ts');
  console.log(`Native audio/recorder vectors equal the web (${downmixes.length} downmixes, ${resamples.length} resamples, ${durations.length} clock values).`);
}
