// Native math parity: the iOS app bundles the exact KaTeX build the web ships and
// renders with the web's own options. This checks (or with --write, copies) the
// bundled files byte for byte and records the web renderLatex output per case.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { KATEX_OPTIONS, renderLatex, type MathKind } from '../src/editor/math';

const require = createRequire(import.meta.url);
const katexDir = dirname(require.resolve('katex/package.json'));
const katexVersion = (JSON.parse(readFileSync(join(katexDir, 'package.json'), 'utf8')) as { version: string }).version;
const here = dirname(fileURLToPath(import.meta.url));
const nativeDir = join(here, '../../ios/ChapterCore/Sources/ChapterCore/KaTeX');
const fixtureURL = join(here, '../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/math-render.json');
const sha = (b: Buffer) => createHash('sha256').update(b).digest('hex');

const files = ['dist/katex.min.js', 'dist/katex.min.css', 'LICENSE',
  ...readdirSync(join(katexDir, 'dist/fonts')).filter(f => f.endsWith('.woff2')).sort().map(f => 'dist/fonts/' + f)];
const target = (f: string) => join(nativeDir, f.replace(/^dist\//, ''));

const inputs: [string, MathKind][] = [
  ['x^2', 'inline'], ['\\frac{a}{b}', 'block'], ['\\sqrt{2}+\\sum_{i=1}^{n} i', 'inline'],
  ['\\begin{pmatrix}1&0\\\\0&1\\end{pmatrix}', 'block'], ['\\mathbb{R}\\to\\mathcal{C}', 'inline'],
  ['\\text{café 👍}', 'inline'], ['\\color{red}{x}', 'inline'], ['\\begin{aligned}a&=b\\\\c&=d\\end{aligned}', 'block'],
  ['\\frac{', 'inline'], ['\\href{https://example.invalid}{x}', 'inline'], ['\\includegraphics{https://example.invalid/a.png}', 'block'],
  ['\\htmlClass{x}{y}', 'inline'], ['\\def\\a{\\a\\a}\\a', 'block'], ['\\rule{1000em}{1000em}', 'inline'], ['', 'inline'], ['<b>&amp;"\'', 'block'],
];

export function verifyMath(write: boolean): void {
  if (write) { for (const f of files) { mkdirSync(dirname(target(f)), { recursive: true }); copyFileSync(join(katexDir, f), target(f)); } }
  for (const f of files) assert.equal(sha(readFileSync(target(f))), sha(readFileSync(join(katexDir, f))), 'Bundled native KaTeX must equal the web build: ' + f);
  const bundled = readdirSync(join(nativeDir, 'fonts')).sort();
  assert.deepEqual(bundled, files.filter(f => f.startsWith('dist/fonts/')).map(f => f.slice('dist/fonts/'.length)), 'Only the web KaTeX woff2 fonts are bundled');
  const fixture = { katexVersion, options: KATEX_OPTIONS, scriptSHA256: sha(readFileSync(join(katexDir, 'dist/katex.min.js'))),
    cases: inputs.map(([latex, kind]) => ({ latex, kind, html: renderLatex(latex, kind) })) };
  for (const c of fixture.cases) assert(!/<(a|img|script|iframe|object|link|style)\b|\son[a-z]+=|javascript:|url\(/i.test(c.html), 'trust:false output must carry no links, images, scripts, styles or handlers: ' + c.latex);
  if (write) writeFileSync(fixtureURL, JSON.stringify(fixture, null, 2) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(fixtureURL, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native math fixtures must equal the web renderLatex');
  console.log(`Native KaTeX ${katexVersion} bundle and ${inputs.length} renderLatex cases equal the web build and options.`);
}
