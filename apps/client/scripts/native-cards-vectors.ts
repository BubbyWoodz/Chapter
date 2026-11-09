// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of video/cards.ts renderTitleCard's layout: the real function
// draws into a recording mock canvas whose measureText uses a fixed width model (shared with the
// Swift test), so wrapping, shrink-to-four-lines, the ellipsis, baselines, rule and counter are the web's.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';

// Width model: per code point, space 0.25em, ASCII 0.5em, anything else 1em; em = the font's px size.
const widthOf = (text: string, px: number): number => { let w = 0; for (const ch of text) w += (ch === ' ' ? 0.25 : ch.charCodeAt(0) < 128 ? 0.5 : 1) * px; return w; };
type Op = Record<string, unknown>;
let ops: Op[] = [];
function mockCanvas(): unknown {
  const ctx = {
    fillStyle: '', strokeStyle: '', lineWidth: 1, font: '10px sans-serif', textAlign: '', textBaseline: '', path: [] as number[][],
    fillRect(x: number, y: number, w: number, h: number) { ops.push({ op: 'rect', x, y, w, h, style: this.fillStyle }); },
    measureText(t: string) { return { width: widthOf(t, Number(/(\d+(?:\.\d+)?)px/.exec(this.font)![1])) }; },
    fillText(text: string, x: number, y: number) { ops.push({ op: 'text', text, x, y, font: this.font, style: this.fillStyle, align: this.textAlign, baseline: this.textBaseline }); },
    beginPath() { this.path = []; }, moveTo(x: number, y: number) { this.path.push([x, y]); }, lineTo(x: number, y: number) { this.path.push([x, y]); },
    stroke() { ops.push({ op: 'line', path: this.path, width: this.lineWidth, style: this.strokeStyle }); },
  };
  return { width: 0, height: 0, getContext: () => ctx };
}
import { renderTitleCard } from '../src/video/cards';
// The DOM stand-ins exist only while the cards render, so the jsdom-based suites are untouched.
async function withMockDOM<T>(run: () => Promise<T>): Promise<T> {
  const g = globalThis as Record<string, unknown>, keys = ['document', 'getComputedStyle', 'createImageBitmap'];
  const saved = keys.map((k) => [k, Object.getOwnPropertyDescriptor(g, k)] as const);
  Object.defineProperty(g, 'document', { value: { documentElement: {}, createElement: () => mockCanvas() }, configurable: true, writable: true });
  Object.defineProperty(g, 'getComputedStyle', { value: () => ({ getPropertyValue: () => '' }), configurable: true, writable: true });
  Object.defineProperty(g, 'createImageBitmap', { value: async () => 'bitmap', configurable: true, writable: true });
  try { return await run(); } finally { for (const [k, d] of saved) { if (d) Object.defineProperty(g, k, d); else delete g[k]; } }
}

const long = 'What is the one thing about the house you grew up in that you would most like your grandchildren to know about, even if they never get to see it themselves?';
const texts = ['Where did you grow up?', '', '   ', ' \t\n Tabs\tand\nnew lines\u00a0and\u3000ideographic\u2028space ', long, long + ' ' + long, long + ' ' + long + ' ' + long,
  'Supercalifragilisticexpialidocious_is_a_single_enormous_word_that_will_never_wrap_anywhere_at_all', 'Olá — qual é a tua memória mais antiga de 日本 e de 😀?',
  'a b c d e f g h i j k l m n o p q r s t u v w x y z', 'One. Two. Three. Four. Five. Six. Seven. Eight. Nine. Ten. Eleven. Twelve. Thirteen.', 'abcdefghi jklmnopqrs', 'abcdefghi jklmnopqrst'];
// 300×280: 24px type and a 234px line, which 'abcdefghi jklmnopqrs' fills exactly (the > vs >= edge);
// 320×180: short enough that the rule's 2px minimum applies.
const sizes: [number, number][] = [[1280, 720], [720, 1280], [640, 360], [720, 720], [1280, 640], [300, 280], [320, 180]];
const counters: [number, number][] = [[1, 6], [12, 12], [0, 0]];

export async function verifyCards(write: boolean): Promise<void> {
  const cases: unknown[] = [];
  await withMockDOM(async () => { for (const [w, h] of sizes) for (const [k, text] of texts.entries()) {
    const [n, total] = counters[k % counters.length];
    ops = [];
    await renderTitleCard(text, n, total, w, h);
    cases.push({ text, n, total, width: w, height: h, ops });
  } });
  const fixture = JSON.parse(JSON.stringify({ theme: { paper: '#f4eee2', ink: '#2a2521', muted: '#a99f8e', accent: '#b0563a', serif: 'Georgia, serif', mono: 'ui-monospace, monospace' }, cases })) as unknown;
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/title-cards.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), fixture, 'Native title-card layout vectors must equal the web renderTitleCard');
  console.log(`Native title-card layout vectors equal the web (${cases.length} cards).`);
}
