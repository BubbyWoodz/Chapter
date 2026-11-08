// Public lossless native/web document fixtures. No personal journal content.
import assert from 'node:assert/strict';
import type { JSONContent } from '@tiptap/core';
import { readFileSync, writeFileSync } from 'node:fs';
import { docToText, docMediaIds } from '../src/editor/doc';
import { decryptRecord } from '../src/sync/engine';
const text = (text: string, marks?: JSONContent["marks"]): JSONContent => ({type:'text', text, ...(marks ? {marks} : {})});
const p = (s: string): JSONContent => ({type:'paragraph', content:[text(s)]});
const media = (id: string) => ({id, mime:'image/png', bytes:10, name:'Public photo'});
const original = {type:'doc', futureRoot:{keep:['all',1,true]}, content:[
 {type:'heading',attrs:{level:2,future:'keep'},content:[text('Public heading',[{type:'bold',attrs:{future:7}}])]},
 {type:'paragraph',content:[text('Hello ',[{type:'bold'},{type:'link',attrs:{href:'https://example.invalid',future:'keep'}}]),text('world 👩🏽‍💻',[{type:'italic'},{type:'underline'},{type:'strike'},{type:'code'}]),{type:'inlineMath',attrs:{latex:'x^2'}},{type:'entryLink',attrs:{entryId:'entry-target',label:'Related'}},{type:'hardBreak'}]},
 {type:'taskList',content:[{type:'taskItem',attrs:{checked:false,future:{keep:true}},content:[p('Task')]}]},
 {type:'table',attrs:{future:1},content:[{type:'tableRow',content:[{type:'tableHeader',attrs:{colspan:1,rowspan:1,colwidth:[160]},content:[p('Header')]},{type:'tableCell',attrs:{colspan:2,rowspan:1,colwidth:null},content:[p('Cell')]}]}]},
 {type:'mediaAttachment',attrs:{...media('attachment'),kind:'image',transcript:'Public transcript'}},
 {type:'mediaGallery',attrs:{images:[media('gallery')]}},
 {type:'blockMath',attrs:{latex:'\\frac{a}{b}'}},
 {type:'blockquote',content:[p('Quotation')]},
 {type:'codeBlock',attrs:{language:'swift'},content:[text('let answer = 42')]},
 {type:'bulletList',content:[{type:'listItem',content:[p('Bullet')]}]},
 {type:'orderedList',attrs:{start:3},content:[{type:'listItem',content:[p('Numbered')]}]},
 {type:'locationMap',attrs:{from:{label:'Home'},to:{label:'Park'},map:media('map'),photo:media('photo'),future:[1,2]}},
 {type:'videoInterview',attrs:{typeName:'Public interview',cards:[{q:'Question?',transcript:'Answer',clip:media('clip')}],film:media('film')}},
 {type:'futureNode',attrs:{secretFormat:{keep:[1,'two',false]}},content:[text('Opaque future text',[{type:'futureMark',attrs:{keep:true}}])]},
]};
const edited = structuredClone(original);
(edited.content[0] as any).content[0].text = 'Edited 📝 heading';
(edited.content[2] as any).content[0].attrs.checked = true;
const previewCases = ['\uFEFFedge\u0085', '\u0085edge\uFEFF', '\t \n spaced \u2028', '👩🏽‍💻 é', '\u200Bnot whitespace\u200B'].map(s => { const doc = {type:'doc',content:[p(s)]}; return {doc,text:docToText(doc)}; });
const fixture = {original, edited, previewCases, originalPreview:docToText(original as any), editedPreview:docToText(edited as any), mediaIds:docMediaIds(original as any)};
export function verifyRichFixture(write: boolean, identity: {dataKey:Uint8Array}, nativePath?: string) {
 const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-document.json',import.meta.url);
 if (write) writeFileSync(url,JSON.stringify(fixture,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(url,'utf8')),fixture,'Frozen native rich fixture drifted from actual web preview/media logic');
 const viewSource = readFileSync(new URL('../../ios/Chapter/RichDocumentViews.swift',import.meta.url),'utf8');
 const publicFixture = /enum PublicRichFixture \{ static let json = #"(.+)"# \}/.exec(viewSource);
 assert(publicFixture, 'Debug public rich fixture missing');
 assert.deepEqual(JSON.parse(publicFixture[1]),original,'UI fixture must equal the golden web document');
 if (nativePath && !write) {
  const output = JSON.parse(readFileSync(nativePath+'.rich','utf8')) as {id:string; record:string};
  const body = JSON.parse(Buffer.from(decryptRecord(identity.dataKey,output.id,Buffer.from(output.record,'base64'))).toString());
  assert.deepEqual(JSON.parse(body.bodyJson),edited,'Native edit lost original nodes, marks or attributes');
  assert.equal(body.bodyText,fixture.editedPreview);
  assert.deepEqual(body.unknownFuture,{preserve:true});
  assert.deepEqual(docMediaIds(JSON.parse(body.bodyJson)),fixture.mediaIds);
  console.log('Swift → actual web: edited rich document, task state, all opaque fields and media references preserved.');
 }
}
