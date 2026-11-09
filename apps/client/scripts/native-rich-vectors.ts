// Public lossless native/web document fixtures. No personal journal content.
import assert from 'node:assert/strict';
import { getSchema, type JSONContent } from '@tiptap/core';
import { readFileSync, writeFileSync } from 'node:fs';
import { buildExtensions, docToText, docMediaIds, docEntryLinks } from '../src/editor/doc';
import { decryptRecord } from '../src/sync/engine';
import { normalizeEntryLabel } from '../src/labels';
import { TableMap } from '@tiptap/pm/tables';
import { defaultEntryTitle } from '../src/state/helpers';
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
const authored = structuredClone(original);
(authored.content[0] as any).content[0].marks.push({type:'italic'});
const authoringBlocks: JSONContent[] = [p('Native paragraph'), ...[1,2,3].map(level => ({type:'heading',attrs:{level},content:[text('Native heading'+level)]})), {type:'blockquote',content:[p('Native blockquote')]}, {type:'bulletList',content:[{type:'listItem',content:[p('Native bulletList')]}]}, {type:'orderedList',content:[{type:'listItem',content:[p('Native orderedList')]}]}, {type:'taskList',content:[{type:'taskItem',attrs:{checked:false},content:[p('Native taskList')]}]}, {type:'codeBlock',content:[text('Native codeBlock')]}];
authored.content.push(...authoringBlocks as any);
// The ACTUAL upstream schema checks supported authored blocks, not opaque future payloads.
const schema = getSchema(buildExtensions(''));
schema.nodeFromJSON({type:'doc',content:authoringBlocks}).check();
schema.nodeFromJSON({type:'doc',content:[{type:'paragraph',content:[text('formatted',[{type:'bold'},{type:'italic'},{type:'underline'},{type:'strike'}])]}, {type:'paragraph',content:[text('code',[{type:'code'}])]}]}).check();
const reordered = structuredClone(original);
reordered.content = [...original.content.filter((_,index) => ![0,2].includes(index)), original.content[0], original.content[2]];
const fixture = {original, edited, authored, reordered, reorderedPreview:docToText(reordered as any), authoredPreview:docToText(authored as any), previewCases, originalPreview:docToText(original as any), editedPreview:docToText(edited as any), mediaIds:docMediaIds(original as any)};
export function verifyRichFixture(write: boolean, identity: {dataKey:Uint8Array}, nativePath?: string) {
 const url = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-document.json',import.meta.url);
 if (write) writeFileSync(url,JSON.stringify(fixture,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(url,'utf8')),fixture,'Frozen native rich fixture drifted from actual web preview/media logic');
 const labelCases = ['  TRAVEL, FRIENDS  ', '\uFEFFWork\u00A0 LIFE\uFEFF', '\u0085X\u0085', '\u200BKeep\u200B', 'İ ΟΣ', '  ', 'MUSIC\n\t NOTES', 'Straße', 'CAFÉ', 'CAFE\u0301'].map(input => ({input,expected:normalizeEntryLabel(input)}));
 const labelURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/entry-labels.json',import.meta.url);
 if (write) writeFileSync(labelURL,JSON.stringify(labelCases,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(labelURL,'utf8')),labelCases,'Native label fixtures must match the original LabelField normalization');
 // Actual prosemirror-tables TableMap over the real web schema: native grid must match.
 const cellNode = (type:string, text:string, attrs?:Record<string,unknown>) => ({type, ...(attrs?{attrs}:{}), content:[{type:'paragraph',content:[{type:'text',text}]}]});
 const td = (t:string,a?:Record<string,unknown>) => cellNode('tableCell',t,a), th = (t:string,a?:Record<string,unknown>) => cellNode('tableHeader',t,a);
 const row = (...cells:unknown[]) => ({type:'tableRow',content:cells});
 const tables:Record<string,unknown> = {
  simpleHeader: {type:'table',content:[row(th('A'),th('B')),row(td('1'),td('2'))]},
  colspan: {type:'table',content:[row(th('Wide',{colspan:2,rowspan:1,colwidth:[120,80]})),row(td('1',{colspan:1,rowspan:1,colwidth:[120]}),td('2',{colspan:1,rowspan:1,colwidth:[80]}))]},
  rowspan: {type:'table',content:[row(td('Tall',{colspan:1,rowspan:2,colwidth:null}),td('a')),row(td('b')),row(td('c'),td('d'))]},
  mixed: {type:'table',content:[row(td('X',{colspan:2,rowspan:2}),td('r')),row(td('s')),row(td('p'),td('q'),td('t'))]},
  missingAfterRowspan: {type:'table',content:[row(td('Down',{colspan:1,rowspan:2}),td('a')),row(td('b'),td('c'))]},
  collision: {type:'table',content:[row(td('A'),td('B',{colspan:1,rowspan:2})),row(td('C',{colspan:2,rowspan:1}))]},
  overlong: {type:'table',content:[row(td('Too tall',{colspan:1,rowspan:3}),td('a')),row(td('b'))]},
  missing: {type:'table',content:[row(td('a'),td('b'),td('c')),row(td('d'))]},
  conflictingWidths: {type:'table',content:[row(td('a',{colwidth:[100]}),td('b')),row(td('c',{colwidth:[140]}),td('d'))]},
 };
 const tableSchema = getSchema(buildExtensions(''));
 const tableCases = Object.entries(tables).map(([name,json]) => {
  const node = tableSchema.nodeFromJSON(json);
  const map = TableMap.get(node);
  const offsets:number[] = [];
  node.forEach((r,rOff) => r.forEach((_c,cOff) => offsets.push(rOff+1+cOff)));
  return {name, table:json, width:map.width, height:map.height, map:Array.from(map.map,(pos:number)=>offsets.indexOf(pos)+1), problems:(map.problems??[]).map((p:{type:string})=>p.type)};
 });
 const tableURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-tables.json',import.meta.url);
 if (write) writeFileSync(tableURL,JSON.stringify(tableCases,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(tableURL,'utf8')),tableCases,'Native table fixtures must equal the actual prosemirror-tables TableMap');
 // Actual web defaultEntryTitle (local wall clock) used for entries started from a template.
 const previousTZ = process.env.TZ;
 const titleCases = ['UTC','America/Los_Angeles','Asia/Kolkata','Pacific/Chatham'].flatMap(tz => [0, 1762675199999, 1773536400000, 4102444800000].map(ms => { process.env.TZ = tz; return {tz, ms, title: defaultEntryTitle(ms)}; }));
 if (previousTZ === undefined) delete process.env.TZ; else process.env.TZ = previousTZ;
 const titleURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/entry-titles.json',import.meta.url);
 if (write) writeFileSync(titleURL,JSON.stringify(titleCases,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(titleURL,'utf8')),titleCases,'Native default entry titles must equal the original defaultEntryTitle');
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
  const nativeLinks = JSON.parse(readFileSync(nativePath+'.entry-links','utf8')) as {ids:string[]};
  assert.deepEqual(nativeLinks.ids,docEntryLinks(original),'Native local links/backlinks must use actual upstream entryId semantics');
  console.log('Native links match the actual original web document collector; navigation does not rewrite encrypted content.');
  const inserted = JSON.parse(readFileSync(nativePath+'.entry-link-insert','utf8')) as {bodyJson:string; bodyText:string};
  const linkedDoc = JSON.parse(inserted.bodyJson) as JSONContent;
  const webNode = {type:'paragraph',content:[{type:'entryLink',attrs:{entryId:'entry-target-2',label:'Linked 📝 é'}},{type:'text',text:' '}]};
  assert.deepEqual(linkedDoc.content?.slice(0,-1),(original as JSONContent).content,'Native link insertion changed existing original blocks');
  assert.deepEqual(linkedDoc.content?.at(-1),webNode,'Native link must be exactly the node wikilink.ts insertEntryLink creates');
  const webSchema = getSchema(buildExtensions(''));
  assert.deepEqual(JSON.parse(JSON.stringify(webSchema.nodeFromJSON(webNode).toJSON())),webNode,'Actual web schema must accept the native link block unchanged');
  assert.deepEqual(docEntryLinks(linkedDoc),[...docEntryLinks(original as JSONContent),'entry-target-2']);
  assert.equal(inserted.bodyText,docToText(linkedDoc),'Native preview/search text must equal the original web docToText');
  console.log('Native link authoring equals the original web [[ insertion node, schema, collector and preview.');
  const template = JSON.parse(readFileSync(nativePath+'.template-authoring','utf8')) as Record<string,unknown>;
  assert.deepEqual(Object.keys(template).sort(),['bodyJson','bodyText','createdAt','kind','name','updatedAt'],'Native template must carry exactly the original templateCodec fields');
  assert.equal(template.kind,'template');assert.equal(template.name,'Morning pages');assert.equal(template.createdAt,template.updatedAt);
  const templateDoc = JSON.parse(template.bodyJson as string) as JSONContent;
  webSchema.nodeFromJSON(templateDoc).check();
  assert.equal(template.bodyText,docToText(templateDoc),'Native template preview text must equal the original web docToText');
  console.log('Native template creation equals the original web createTemplate fields, schema and preview text.');
  const arranged = JSON.parse(readFileSync(nativePath+'.rich-structure','utf8')) as {id:string;record:string};
  const arrangedBody = JSON.parse(Buffer.from(decryptRecord(identity.dataKey,arranged.id,Buffer.from(arranged.record,'base64'))).toString());
  assert.deepEqual(JSON.parse(arrangedBody.bodyJson),reordered,'Native block move lost, flattened or rewrote an original/opaque block');
  assert.equal(arrangedBody.bodyText,fixture.reorderedPreview);
  assert.deepEqual(docMediaIds(JSON.parse(arrangedBody.bodyJson)),fixture.mediaIds);
  assert.deepEqual(arrangedBody.unknownFuture,{preserve:true});
  console.log('Swift → actual web: genuine whole-block rearrangement, full original/opaque trees, preview and every media reference preserved.');
  const authoring = JSON.parse(readFileSync(nativePath+'.rich-authoring','utf8')) as {id:string;record:string};
  const authoredBody = JSON.parse(Buffer.from(decryptRecord(identity.dataKey,authoring.id,Buffer.from(authoring.record,'base64'))).toString());
  assert.deepEqual(JSON.parse(authoredBody.bodyJson),authored,'Native formatting/structural insertion lost content');
  assert.equal(authoredBody.bodyText,fixture.authoredPreview);
  assert.deepEqual(docMediaIds(JSON.parse(authoredBody.bodyJson)),fixture.mediaIds);
  assert.deepEqual(authoredBody.unknownFuture,{preserve:true});
  const moved = JSON.parse(readFileSync(nativePath+'.entry-move','utf8')) as {id:string;record:string};
  const movedBody = JSON.parse(Buffer.from(decryptRecord(identity.dataKey,moved.id,Buffer.from(moved.record,'base64'))).toString());
  assert.equal(movedBody.journalId,'public-destination');assert.equal(movedBody.createdAt,1);
  assert.deepEqual(JSON.parse(movedBody.bodyJson),original);assert.deepEqual(movedBody.unknownFuture,{preserve:true});
  assert.deepEqual(docMediaIds(JSON.parse(movedBody.bodyJson)),fixture.mediaIds);
  const metadata = JSON.parse(readFileSync(nativePath+'.entry-metadata','utf8')) as {id:string;record:string};
  const metadataBody = JSON.parse(Buffer.from(decryptRecord(identity.dataKey,metadata.id,Buffer.from(metadata.record,'base64'))).toString());
  assert.deepEqual(JSON.parse(metadataBody.bodyJson),original);assert.equal(metadataBody.bodyText,fixture.originalPreview);
  assert.equal(metadataBody.title,'Native metadata');assert.equal(metadataBody.createdAt,1700000000000);
  assert.equal(metadataBody.journalId,'original');assert.deepEqual(metadataBody.labels,['travel, friends','ImportedCase']);
  assert.deepEqual(metadataBody.unknownFuture,{preserve:true});assert.deepEqual(docMediaIds(JSON.parse(metadataBody.bodyJson)),fixture.mediaIds);
  console.log('Swift → actual web: title/date/individual labels (including comma) retain exact original rich tree, opaque metadata and every media reference.');
  console.log('Swift → actual web: moved rich entry retains original content, dates, opaque fields and every media reference.');
  console.log('Swift → actual web: all nine authored block styles + native formatting preserve every original node/attribute/media reference; genuine upstream schema accepts new blocks.');
 }
}
