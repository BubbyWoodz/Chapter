// SPDX-License-Identifier: AGPL-3.0-or-later
// Golden vectors for the native port of the Day One importer's pure parts:
// import/markdown.ts markdownToBlocks + splitTitle and import/dayone.ts parseMomentUrl.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { markdownToBlocks, splitTitle } from '../src/import/markdown';
import { parseMomentUrl } from '../src/import/dayone';

const md: string[] = [
  '# Trip to Lisbon\n\nWe landed at **noon** and walked to the *river*.\n\n![](dayone-moment://3F2A1B)\n![](dayone-moment://9C8D7E)\n\nDinner at [Taberna](https://example.com/t?a=1_b).',
  'First line is the title\nsecond line stays in the body\nthird too',
  'A'.repeat(150), 'B'.repeat(150) + '\nrest', '😀'.repeat(80) + '\nemoji title cut inside a pair',
  '   \n\n## Spaced heading   \n\n- one\n- two\n* three\n+ four\n\n1. first\n2) second\n\n- [ ] todo\n- [x] done\n- [X] DONE\n- plain after tasks',
  '> quoted **bold**\n> second\n>\n> third\n\nafter',
  '```js\nconst a = 1;\n\n```\n```\nno lang\n```\n```unterminated\nline',
  '---\n***\n___\n- - -\nText',
  'Escapes: \\*not italic\\* and \\`tick and \\\\ backslash\\',
  'Code `a*b*c` and `unclosed and **bold *in* bold** and __under__ and _it_ and *it2*',
  'Link with bad scheme [click](javascript:alert(1)) and [mail](MAILTO:x@y) and [rel](/p) and [](https://empty) and [x](  )',
  'Nested [**bold link**](https://a.b) and ![alt](https://not-a-moment/img.png) and ![x](dayone-moment:/video/ABC-123) ![y](dayone-moment:/audio/A1) ![z](dayone-moment:/pdfAttachment/P9) ![w](dayone-moment:/other/Q)',
  'Inline image in heading\n# H ![](dayone-moment://IMG1)\n- item ![](dayone-moment://IMG2)',
  '\r\nWindows\r\nline endings\rold mac\r\n\r\n# H\r\n',
  'trailing  \u00a0\n\u2028still para\u2028\ufeff\n\u0085next',
  '#nospace\n####### seven\n#\ttab heading\n# \n#   ',
  '1.nospace\n10. ten\n-nospace\n-  [ ]  spaced task',
  '**unclosed bold and *x',
  '* * *\n*a* *',
  '',
  '\n\n\n',
  '![](dayone-moment://ONLY)',
  '# \n\nBody after empty heading',
  '**Bold title**\nBody',
  '[link title](https://x.y)\nbody',
  'Title\u2028with LS\nbody',
  '#\ufeffBOM heading\n-\ufeffBOM item\n#\u0085NEL not a heading\n-\u0085NEL not an item\n>\ufeffquote',
  '#### four\n##### five\n###### six\n```\ufeff\ncode after BOM fence\n```',
];
const urls = ['dayone-moment://ABC', 'dayone-moment:/ABC', 'dayone-moment:///ABC', 'dayone-moment://video/V1', 'dayone-moment:/video/V1', 'dayone-moment://video', 'dayone-moment://audio/', 'dayone-moment://pdfAttachment/P_1', 'dayone-moment://a-b-c?x', 'dayone-moment:ABC', 'https://x', 'dayone-moment://', 'DAYONE-MOMENT://A', 'dayone-moment://Ä'];

export function verifyDayOne(write: boolean): void {
  const cases = md.map((text) => { const blocks = markdownToBlocks(text); return { md: text, blocks, split: splitTitle(blocks) }; });
  const moments = urls.map((url) => ({ url, ref: parseMomentUrl(url) }));
  const fixture = JSON.parse(JSON.stringify({ cases, moments }));
  const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/dayone-markdown.json', import.meta.url);
  if (write) writeFileSync(url, JSON.stringify(fixture, null, 1) + '\n');
  else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), fixture, 'Native Day One vectors must equal the web importer');
  console.log(`Native Day One markdown vectors equal the web importer (${cases.length} documents, ${moments.length} moment URLs).`);
}
