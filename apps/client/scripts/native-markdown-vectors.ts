// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of editor/markdown.ts `docToMarkdown` and of
// JavaScript's JSON.parse/JSON.stringify (the export's markdown field, mneme:* fences).
// Every case is a raw bodyJson string, so key order, duplicate keys, index-like keys,
// escapes and number spellings reach the native parser exactly as stored.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { docToMarkdown } from '../src/editor/markdown';

const fx = (p: string): any => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const t = (text: string, marks?: unknown[]): unknown => (marks ? { type: 'text', text, marks } : { type: 'text', text });
const p = (...content: unknown[]): unknown => ({ type: 'paragraph', content });
const doc = (...content: unknown[]): string => JSON.stringify({ type: 'doc', content });

function corpus(): string[] {
  const rich = fx('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-document.json');
  const out: string[] = ['original', 'edited', 'authored', 'reordered'].map((k) => JSON.stringify(rich[k]));
  for (const c of Object.values(rich.previewCases ?? {}) as { doc?: unknown }[]) if (c && c.doc) out.push(JSON.stringify(c.doc));
  for (const tb of fx('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-tables.json') as { table: unknown }[]) out.push(doc(tb.table));
  const seeds = fx('../../ios/ChapterCore/Sources/ChapterCore/Resources/builtin-templates-locales.json').seeds as Record<string, { bodyJson: string }[]>;
  for (const list of Object.values(seeds)) for (const s of list) out.push(s.bodyJson);
  const link = (href: unknown): unknown => ({ type: 'link', attrs: { href } });
  out.push(
    // Inline marks, escaping, links (allowed, relative, blocked, obfuscated), code with odd text.
    doc(p(t('a*b_c`d~e$f[g]h\\i'), t('bold', [{ type: 'bold' }]), t('it', [{ type: 'italic' }]), t('both', [{ type: 'italic' }, { type: 'bold' }]), t('gone', [{ type: 'strike' }]))),
    doc(p(t('x', [link('https://e.com/a_b')]), t('y', [link('/rel')]), t('z', [link('#frag')]), t('j', [link('java\tscript:alert(1)')]), t('m', [link('MAILTO:a@b')]), t('d', [link('data:x')]), t('e', [link('\u200b')]), t('n', [link(5)]), t('s', [link(' https://x')]), t('sp', [link(' javascript:alert(1)')]), t('nb', [link('\u00a0javascript:x')]), t('ok', [link('a+b.c-d:x')]))),
    doc(p(t('code *x*', [{ type: 'code' }, { type: 'bold' }]))),
    JSON.stringify({ type: 'doc', content: [p({ type: 'text', text: 42, marks: [{ type: 'code' }] }, { type: 'text', text: [1, null, [2, { a: 1 }], true], marks: [{ type: 'code' }] }, { type: 'text', text: null })] }),
    JSON.stringify({ type: 'doc', content: [p({ type: 'text', text: 42 })] }),
    JSON.stringify({ type: 'doc', content: [p({ type: 'text', text: 'x', marks: 'bold' })] }),
    JSON.stringify({ type: 'doc', content: [p({ type: 'text', text: 'x', marks: [null] })] }),
    JSON.stringify({ type: 'doc', content: [p({ type: 'text', text: 'x', marks: ['bold', { type: 'link' }, { type: 'link', attrs: { href: 'http://first' } }] })] }),
    doc(p(t('line'), { type: 'hardBreak' }, t('next'), { type: 'inlineMath', attrs: { latex: 'x^2' } }, { type: 'inlineMath' }, { type: 'entryLink', attrs: { entryId: 'e1', label: 'L|b' } }, { type: 'entryLink', attrs: { entryId: 7 } }, { type: 'mystery' }, 'str', 3)),
    // Headings: levels, clamps, non-numbers, fractions, huge.
    JSON.stringify({ type: 'doc', content: [0, 1, 2, 3, 4, 2.9, -5, 1e400, '2', null, true].map((level) => ({ type: 'heading', attrs: { level }, content: [t('H')] })).concat([{ type: 'heading', content: [t('none')] } as never]) }),
    // Lists: ordered starts, nesting, task truthiness, empty items, multi-block items.
    JSON.stringify({ type: 'doc', content: [
      { type: 'orderedList', attrs: { start: 9 }, content: [{ type: 'listItem', content: [p(t('nine'))] }, { type: 'listItem', content: [p(t('ten')), { type: 'bulletList', content: [{ type: 'listItem', content: [p(t('deep')), p(t('para2'))] }] }, p(t('after'))] }] },
      { type: 'orderedList', attrs: { start: 0 }, content: [{ type: 'listItem', content: [] }] },
      { type: 'orderedList', attrs: { start: 1.5 }, content: [{ type: 'listItem', content: [p(t('a'))] }, { type: 'listItem', content: [p(t('b'))] }] },
      { type: 'orderedList', attrs: { start: 1e21 }, content: [{ type: 'listItem', content: [p(t('big'))] }] },
      { type: 'orderedList', attrs: { start: 123456789012345680000 }, content: [{ type: 'listItem', content: [p(t('n'))] }] },
      { type: 'taskList', content: [true, 1, 0, '', 'no', null, {}, []].map((checked) => ({ type: 'taskItem', attrs: { checked }, content: [p(t('task'))] })) },
      { type: 'taskList', content: [{ type: 'taskItem', content: [{ type: 'taskList', content: [{ type: 'taskItem', attrs: { checked: true }, content: [p(t('nested'))] }] }] }] },
      { type: 'bulletList', content: [{ type: 'listItem', content: [{ type: 'blockquote', content: [p(t('quoted\nlines'))] }] }] },
    ] }),
    // Blocks: quotes, code fences, math, rules, unknown, media, galleries.
    JSON.stringify({ type: 'doc', content: [
      { type: 'blockquote', content: [p(t('q1')), { type: 'blockquote', content: [p(t('q2'))] }] },
      { type: 'codeBlock', attrs: { language: 'js' }, content: [t('let a = ```;\n````'), { type: 'hardBreak' }, { type: 'text', text: 5 }, { type: 'text', text: null }] },
      { type: 'codeBlock', attrs: { language: 3 } },
      { type: 'blockMath', attrs: { latex: '\\frac12' } }, { type: 'blockMath' }, { type: 'horizontalRule' },
      { type: 'mediaAttachment', attrs: { id: 'm1', kind: 'audio', mime: 'audio/mp4', durationMs: 1500.5, createdAt: 1e400, name: 'é "q" \u0001\u2028' } },
      { type: 'mediaGallery', attrs: { images: [{ id: 'g1', width: -0, height: 1e-7 }] } },
      { type: 'locationMap', attrs: { from: 'A', to: 'B' } }, 'plain string block', 7, [1, 2], { noType: true },
      p(), p(t('')), { type: 'paragraph', content: '' }, { type: 'paragraph', content: 0 },
    ] }),
    // Tables: simple, escaped pipes, merged, multi-block, strings as rows/cells, empty.
    JSON.stringify({ type: 'doc', content: [
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableHeader', content: [p(t('a|b\\c'))] }, { type: 'tableHeader', content: [p(t('h', [{ type: 'bold' }]))] }] }, { type: 'tableRow', content: [{ type: 'tableCell', attrs: { colspan: 1, rowspan: 1 }, content: [p()] }, { type: 'tableCell', content: [p(t('x'))] }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', attrs: { colspan: 2 }, content: [p(t('merged'))] }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', attrs: { colspan: '1' }, content: [p(t('string span'))] }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: [p(t('1')), p(t('2'))] }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: [{ type: 'heading', content: [t('h')] }] }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: 'p' }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: null }] }] },
      { type: 'table', content: [{ type: 'tableRow', content: 'ab' }] },
      { type: 'table', content: [{ type: 'tableRow' }] }, { type: 'table', content: [] }, { type: 'table' }, { type: 'table', content: '' },
    ] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'table', content: 'rows' }] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'table', content: [{ type: 'tableRow', content: '' }] }] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'table', content: [{ type: 'tableRow', content: [null] }] }] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'table', content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: [null] }] }] }] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'table', content: { 0: 'x' } }] }),
    // Shapes that make the web serializer throw (the export then uses bodyText).
    JSON.stringify({ type: 'doc', content: [null] }), JSON.stringify({ type: 'doc', content: 'abc' }), JSON.stringify({ type: 'doc', content: {} }),
    JSON.stringify({ type: 'doc', content: [{ type: 'bulletList', content: [null] }] }), JSON.stringify({ type: 'doc', content: [{ type: 'bulletList', content: [{ type: 'listItem', content: [null] }] }] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'taskList', content: [null] }] }), JSON.stringify({ type: 'doc', content: [p(null)] }), JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: true }] }),
    JSON.stringify({ type: 'doc', content: [{ type: 'codeBlock', content: [null] }] }), JSON.stringify({ type: 'doc', content: [{ type: 'codeBlock', content: 'x' }] }),
    // Whole-document edges, and raw JSON spellings JSON.stringify must reproduce.
    '[]', '{}', '{"type":"doc"}', '{"type":"doc","content":null}', '[{"type":"paragraph"}]',
    '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"dup","text":"last"}]}]}',
    '{"type":"doc","content":[{"type":"mediaAttachment","attrs":{"z":1,"10":2,"2":3,"a":4,"01":5,"4294967295":6,"4294967294":7,"-1":8},"type":"mediaAttachment"}]}',
    '{"type":"doc","content":[{"type":"mystery","attrs":{"n":[1E2,1e-7,123e-20,0.1,-0,5e-324,1.7976931348623157e308,1e21,1e400,-1e400,100,0.000001,123456789012345678901234]}}]}',
    '{"type":"doc","content":[{"type":"mystery","attrs":{"s":"\\u00e9\\ud83d\\ude00\\/\\b\\f\\n\\r\\t\\u001f\\u007f\\u2028\\"\\\\","lone":"\\ud800x","rev":"\\udc00\\ud800"}}]}',
    ' \t\n\r{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"  ws  "}]}]} \n',
    '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\\n\\n\\n\\nx\\u2028\\n\\n\\n\\u00a0"}]}]}',
    '"just a string"', '42', 'null', 'true', '{"a":1,}', '[1,]', '01', '{"a":"\t"}', "{'a':1}", '{"a":1} x', '', ' ', '-', '1.', '.5', '1e', '+1', 'NaN', '{"a":"\\x"}', '{"a":"\\u12"}', '[1 2]', '{"a" 1}', '\u00a0{}', '{"__proto__":{"type":"x"},"type":"doc","content":[]}',
  );
  return out;
}

export function verifyMarkdown(write: boolean): void {
  const cases = corpus().map((json) => {
    let parsed: unknown;
    try { parsed = JSON.parse(json); } catch { return { json, parsed: false }; }
    const base = { json, parsed: true, stringify: JSON.stringify(parsed) };
    if (!parsed || typeof parsed !== 'object') return base;
    try { return { ...base, markdown: docToMarkdown(parsed as never) }; } catch { return { ...base, throws: true }; }
  });
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/markdown.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(cases, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), cases, 'Native markdown vectors must equal the web docToMarkdown');
  const n = (k: string): number => cases.filter((c) => k in c).length;
  console.log(`Native docToMarkdown vectors equal the web (${cases.length} cases: ${n('markdown')} rendered, ${n('throws')} throwing, ${cases.filter((c) => !c.parsed).length} rejected by JSON.parse).`);
}
