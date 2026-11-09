// Public lossless native/web document fixtures. No personal journal content.
import assert from 'node:assert/strict';
import { Editor, getSchema, createNodeFromContent, type JSONContent } from '@tiptap/core';
import { JSDOM } from 'jsdom';
import { Fragment, type Node as PMNode } from '@tiptap/pm/model';
import { EditorState } from '@tiptap/pm/state';
import { readFileSync, writeFileSync } from 'node:fs';
import { buildExtensions, docToText, docMediaIds, docEntryLinks } from '../src/editor/doc';
import { decryptRecord } from '../src/sync/engine';
import { normalizeEntryLabel } from '../src/labels';
import { TableMap } from '@tiptap/pm/tables';
import { defaultEntryTitle } from '../src/state/helpers';
import { seedBuiltinTemplates } from '../src/data/templates';
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
 // At-cursor insertion, computed by the real ProseMirror transform exactly as
 // TipTap insertContentAt does for a collapsed cursor (wikilink insertEntryLink
 // inserts [entryLink, " "]; Editor insertTemplate inserts the template's blocks).
 const caretSchema = getSchema(buildExtensions(''));
 const insertAtCaret = (docJSON:JSONContent, block:number[], offset:number, value:JSONContent[]):JSONContent => {
  const doc = caretSchema.nodeFromJSON(docJSON); const tr = EditorState.create({doc,schema:caretSchema}).tr;
  let pos = 0; let node:PMNode = doc;
  for (const i of block) { for (let j = 0; j < i; j++) pos += node.child(j).nodeSize; pos += 1; node = node.child(i); }
  pos += offset;
  const content = createNodeFromContent(value, caretSchema, {parseOptions:{preserveWhitespace:'full'}});
  const nodes: readonly PMNode[] = content instanceof Fragment ? (content as unknown as {content: readonly PMNode[]}).content : [content as PMNode];
  let from = pos, to = pos, onlyText = true, onlyBlock = true;
  nodes.forEach(n => { n.check(); onlyText = onlyText ? n.isText && n.marks.length === 0 : false; onlyBlock = onlyBlock ? n.isBlock : false; });
  if (onlyBlock) { const {parent} = tr.doc.resolve(from); if (parent.isTextblock && !parent.type.spec.code && !parent.childCount) { from -= 1; to += 1; } }
  if (onlyText) tr.insertText(nodes.map(n => n.text ?? '').join(''), from, to);
  else { const $f = tr.doc.resolve(from); const n = $f.node(); if ($f.parentOffset === 0 && n.isTextblock && n.content.size > 0 && onlyBlock) from = Math.max(0, from - 1); tr.replaceWith(from, to, nodes); }
  return tr.doc.toJSON() as JSONContent;
 };
 const cp = (...c:JSONContent[]):JSONContent => c.length ? {type:'paragraph',content:c} : {type:'paragraph'};
 const ct = (text:string, marks?:JSONContent['marks']):JSONContent => marks ? {type:'text',text,marks} : {type:'text',text};
 const bold = [{type:'bold'}], link = [{type:'link',attrs:{href:'https://example.invalid',target:'_blank',rel:'noopener noreferrer nofollow',class:null}}];
 const linkNodes = (id:string):JSONContent[] => [{type:'entryLink',attrs:{entryId:id,label:'Linked 📝'}},{type:'text',text:' '}];
 const tplA:JSONContent[] = [{type:'heading',attrs:{level:2},content:[ct('Prompt')]},cp()];
 const tplB:JSONContent[] = [cp(ct('First')),{type:'bulletList',content:[{type:'listItem',content:[cp()]}]}];
 const tplC:JSONContent[] = [{type:'table',content:[{type:'tableRow',content:[{type:'tableHeader',attrs:{colspan:1,rowspan:1,colwidth:null},content:[cp(ct('H'))]}]}]}];
 const caretDocs:Record<string,JSONContent> = {
  plain:{type:'doc',content:[cp(ct('Hello world')),{type:'heading',attrs:{level:2},content:[ct('Head')]},cp()]},
  marks:{type:'doc',content:[cp(ct('ab',bold),ct('cd'))]},
  leaves:{type:'doc',content:[cp(ct('ab'),{type:'entryLink',attrs:{entryId:'old',label:'Old'}},ct('cd',bold)),cp(ct('a'),{type:'hardBreak'},ct('b'))]},
  emoji:{type:'doc',content:[cp(ct('a👩🏽‍💻b'))]},
  nested:{type:'doc',content:[{type:'bulletList',content:[{type:'listItem',content:[cp(ct('Item text'))]}]},{type:'table',content:[{type:'tableRow',content:[{type:'tableCell',attrs:{colspan:1,rowspan:1,colwidth:null},content:[cp(ct('Cell'))]}]}]}]},
  linked:{type:'doc',content:[{type:'heading',attrs:{level:3},content:[ct('Go here',link)]}]},
 };
 const caretInputs:[string,string,number[],number,JSONContent[]][] = [
  ['link mid plain','plain',[0],5,linkNodes('t1')], ['link start','plain',[0],0,linkNodes('t1')], ['link end','plain',[0],11,linkNodes('t1')],
  ['link empty paragraph','plain',[2],0,linkNodes('t1')], ['link inside bold','marks',[0],1,linkNodes('t1')], ['link bold boundary merges space','marks',[0],2,linkNodes('t1')],
  ['link end of marked text','marks',[0],4,linkNodes('t1')], ['link after existing link before bold','leaves',[0],3,linkNodes('t1')], ['link after hard break','leaves',[1],2,linkNodes('t1')],
  ['link after emoji','emoji',[0],8,linkNodes('t1')], ['link in list item','nested',[0,0,0],4,linkNodes('t1')], ['link in table cell','nested',[1,0,0,0],2,linkNodes('t1')],
  ['link inside link mark heading','linked',[0],2,linkNodes('t1')],
  ['template start','plain',[0],0,tplA], ['template mid','plain',[0],5,tplA], ['template end','plain',[0],11,tplA], ['template empty paragraph','plain',[2],0,tplA],
  ['template heading mid paragraph-first','plain',[1],2,tplB], ['template paragraph mid paragraph-first','plain',[0],6,tplB], ['template table','marks',[0],2,tplC],
  ['template after leaf nodes','leaves',[0],3,tplA],
 ];
 const caretCases = caretInputs.map(([name,docName,block,offset,insert]) => ({name, doc:caretDocs[docName], block, offset, insert, expected:insertAtCaret(caretDocs[docName],block,offset,insert)}));
 // Selection formatting: the real TipTap Editor (original extensions) runs the
 // toolbar's toggleMark over a selection inside one text leaf, headless in jsdom.
 const dom = new JSDOM('<!doctype html><html><body></body></html>');
 const g = globalThis as Record<string, unknown>;
 for (const k of ['window','document','Node','HTMLElement','Element','Text','MutationObserver','DOMParser','getComputedStyle']) if (g[k] === undefined) g[k] = (dom.window as unknown as Record<string, unknown>)[k];
 const markOrder = Object.keys(caretSchema.marks);
 const markExclusions = Object.fromEntries(markOrder.map(a => [a, markOrder.filter(b => b !== a && caretSchema.marks[a].excludes(caretSchema.marks[b]))]).filter(([, v]) => (v as string[]).length));
 const leafPos = (docJSON:JSONContent, leaf:number[]):number => {
  const doc = caretSchema.nodeFromJSON(docJSON); let pos = 0; let node:PMNode = doc;
  leaf.forEach((i, depth) => { for (let j = 0; j < i; j++) pos += node.child(j).nodeSize; if (depth < leaf.length - 1) pos += 1; node = node.child(i); });
  return pos;
 };
 const toggleInEditor = (docJSON:JSONContent, leaf:number[], from:number, to:number, mark:string):JSONContent => {
  const editor = new Editor({extensions:buildExtensions(''), content:docJSON});
  // Load must not normalise anything, so the result isolates toggleMark itself.
  assert.deepEqual(JSON.parse(JSON.stringify(editor.getJSON())),JSON.parse(JSON.stringify(caretSchema.nodeFromJSON(docJSON).toJSON())),'TipTap load changed a selection fixture');
  const base = leafPos(docJSON, leaf);
  editor.chain().setTextSelection({from:base + from, to:base + to}).toggleMark(mark).run();
  const out = JSON.parse(JSON.stringify(editor.getJSON())) as JSONContent; editor.destroy(); return out;
 };
 const endsInParagraph = (d:JSONContent):JSONContent => d.content?.at(-1)?.type === 'paragraph' ? d : {...d, content:[...(d.content ?? []), cp()]};
 const selDocs:Record<string,JSONContent> = {
  ...Object.fromEntries(Object.entries(caretDocs).map(([k, d]) => [k, endsInParagraph(d)])),
  italic:{type:'doc',content:[cp(ct('xy',[{type:'italic'}]),ct('z'))]},
  sandwich:{type:'doc',content:[cp(ct('a',[{type:'underline'}]),ct('b'),ct('c',[{type:'underline'}]))]},
  code:{type:'doc',content:[cp(ct('ab',bold),ct('code',[{type:'code'}]))]},
  block:{type:'doc',content:[{type:'codeBlock',attrs:{language:'swift'},content:[ct('let x')]},cp()]},
 };
 const selInputs:[string,string,number[],number,number,string][] = [
  ['bold word','plain',[0,0],6,11,'bold'], ['italic across space','plain',[0,0],3,7,'italic'], ['code word','plain',[0,0],0,5,'code'],
  ['bold whole heading','plain',[1,0],0,4,'bold'], ['strike middle','plain',[0,0],2,4,'strike'], ['underline end','plain',[0,0],10,11,'underline'],
  ['bold joins left','marks',[0,1],0,1,'bold'], ['bold removes inside','marks',[0,0],1,2,'bold'], ['bold removes all joins','marks',[0,0],0,2,'bold'],
  ['italic on bold rank order','marks',[0,0],0,1,'italic'], ['bold on italic rank order','italic',[0,0],0,2,'bold'], ['italic removed partly','italic',[0,0],1,2,'italic'],
  ['underline joins both sides','sandwich',[0,1],0,1,'underline'], ['code drops bold','code',[0,0],0,1,'code'], ['code removed','code',[0,1],1,3,'code'],
  ['bold on code no-op','code',[0,1],0,2,'bold'], ['bold inside link','linked',[0,0],0,2,'bold'], ['bold emoji whole','emoji',[0,0],1,8,'bold'],
  ['bold next to entry link','leaves',[0,0],1,2,'bold'], ['italic after hard break','leaves',[1,2],0,1,'italic'], ['bold in list item','nested',[0,0,0,0],0,4,'bold'],
  ['bold in table cell','nested',[1,0,0,0,0],1,3,'bold'], ['bold in code block no-op','block',[0,0],0,3,'bold'],
 ];
 const selCases = selInputs.map(([name,docName,leaf,from,to,mark]) => ({name, doc:selDocs[docName], leaf, from, to, mark, expected:toggleInEditor(selDocs[docName],leaf,from,to,mark)}));
 // Table editing: the original toolbar's prosemirror-tables commands, run by the
 // real TipTap Editor with the cursor inside one cell (row, column).
 const cellPos = (docJSON:JSONContent, table:number[], row:number, col:number):number => leafPos(docJSON,[...table,row,col,0]) + 1;
 const tableCommand = (docJSON:JSONContent, table:number[], row:number, col:number, command:string):JSONContent => {
  const editor = new Editor({extensions:buildExtensions(''), content:docJSON});
  assert.deepEqual(JSON.parse(JSON.stringify(editor.getJSON())),JSON.parse(JSON.stringify(caretSchema.nodeFromJSON(docJSON).toJSON())),'TipTap load changed a table fixture');
  editor.commands.setTextSelection(cellPos(docJSON,table,row,col));
  (editor.chain() as unknown as Record<string,() => {run:() => boolean}>)[command]().run();
  const out = JSON.parse(JSON.stringify(editor.getJSON())) as JSONContent; editor.destroy(); return out;
 };
 const tc = (text?:string):JSONContent => ({type:'tableCell',attrs:{colspan:1,rowspan:1,colwidth:null},content:[text ? cp(ct(text)) : cp()]});
 const thc = (text?:string, colwidth:number[]|null = null):JSONContent => ({type:'tableHeader',attrs:{colspan:1,rowspan:1,colwidth},content:[text ? cp(ct(text)) : cp()]});
 const tr = (...cells:JSONContent[]):JSONContent => ({type:'tableRow',content:cells});
 const editTables:Record<string,JSONContent> = {
  header:{type:'doc',content:[cp(ct('Before')),{type:'table',content:[tr(thc('A',[120]),thc('B')),tr(tc('1'),tc('2')),tr(tc('3'),tc('4'))]},cp(ct('After'))]},
  plain:{type:'doc',content:[{type:'table',content:[tr(tc('a'),tc('b'),tc('c')),tr(tc('d'),tc('e'),tc('f'))]},cp()]},
  single:{type:'doc',content:[{type:'table',content:[tr(thc('Only'))]},cp()]},
  headerColumn:{type:'doc',content:[{type:'table',content:[tr(thc('H'),thc('X')),tr(thc('R'),tc('v'))]},cp()]},
  nested:{type:'doc',content:[{type:'blockquote',content:[{type:'table',content:[tr(tc('q'),tc(''))]}]},cp()]},
  votes:{type:'doc',content:[{type:'table',content:[tr(thc('w',[100]),thc('x')),tr({...tc('y'),attrs:{colspan:1,rowspan:1,colwidth:[200]}},tc('z')),tr({...tc('u'),attrs:{colspan:1,rowspan:1,colwidth:[200]}},tc('v')),tr(tc('t'),tc('s'))]},cp()]},
 };
 const tableEditInputs:[string,string,number[],number,number,string][] = [
  ['row after header','header',[1],0,1,'addRowAfter'], ['row after body','header',[1],1,0,'addRowAfter'], ['row after last','header',[1],2,1,'addRowAfter'],
  ['column after first','header',[1],1,0,'addColumnAfter'], ['column after last','header',[1],0,1,'addColumnAfter'], ['delete body row','header',[1],1,1,'deleteRow'],
  ['delete header row','header',[1],0,0,'deleteRow'], ['delete first column','header',[1],2,0,'deleteColumn'], ['toggle header off','header',[1],2,1,'toggleHeaderRow'],
  ['toggle header on','plain',[0],1,2,'toggleHeaderRow'], ['row after plain','plain',[0],0,2,'addRowAfter'], ['column middle plain','plain',[0],1,1,'addColumnAfter'],
  ['delete middle column','plain',[0],0,1,'deleteColumn'], ['delete table','header',[1],1,0,'deleteTable'], ['delete only row no-op','single',[0],0,0,'deleteRow'],
  ['delete only column no-op','single',[0],0,0,'deleteColumn'], ['row after single header','single',[0],0,0,'addRowAfter'], ['column after single header','single',[0],0,0,'addColumnAfter'],
  ['toggle header with header column','headerColumn',[0],1,1,'toggleHeaderRow'], ['column after header column','headerColumn',[0],1,0,'addColumnAfter'], ['row after header row and column','headerColumn',[0],0,1,'addRowAfter'],
  ['nested row after','nested',[0,0],0,1,'addRowAfter'], ['nested delete table','nested',[0,0],0,0,'deleteTable'],
  ['width vote after column','votes',[0],1,1,'addColumnAfter'],
 ];
 const tableEditCases = tableEditInputs.map(([name,docName,table,row,col,command]) => ({name, doc:editTables[docName], table, row, col, command, expected:tableCommand(editTables[docName],table,row,col,command)}));
 const tableEditURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-table-edit.json',import.meta.url);
 if (write) writeFileSync(tableEditURL,JSON.stringify(tableEditCases,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(tableEditURL,'utf8')),JSON.parse(JSON.stringify(tableEditCases)),'Native table-edit fixtures must equal the actual prosemirror-tables commands');
 const selURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-selection.json',import.meta.url);
 const selFixture = {markOrder, markExclusions, cases:selCases};
 if (write) writeFileSync(selURL,JSON.stringify(selFixture,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(selURL,'utf8')),JSON.parse(JSON.stringify(selFixture)),'Native selection fixtures must equal the actual TipTap toggleMark');
 const caretURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/rich-caret.json',import.meta.url);
 if (write) writeFileSync(caretURL,JSON.stringify(caretCases,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(caretURL,'utf8')),JSON.parse(JSON.stringify(caretCases)),'Native caret fixtures must equal the actual ProseMirror insertion');
 // Actual web built-in template seeds (English catalog), exactly as seedBuiltinTemplates lays them down.
 const builtins = seedBuiltinTemplates(0).map(t => ({slug:t.builtin, name:t.name, bodyJson:t.bodyJson, bodyText:t.bodyText}));
 const builtinURL = new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/builtin-templates.json',import.meta.url);
 if (write) writeFileSync(builtinURL,JSON.stringify(builtins,null,2)+'\n');
 else assert.deepEqual(JSON.parse(readFileSync(builtinURL,'utf8')),builtins,'Native built-in templates must equal the original web seeds');
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
  const nativeCarets = JSON.parse(readFileSync(nativePath+'.rich-caret','utf8')) as JSONContent[];
  assert.equal(nativeCarets.length,caretCases.length);
  nativeCarets.forEach((doc,i) => assert.deepEqual(JSON.parse(JSON.stringify(webSchema.nodeFromJSON(doc).toJSON())),JSON.parse(JSON.stringify(caretCases[i].expected)),'Native at-cursor insertion differs from ProseMirror: '+caretCases[i].name));
  console.log('Native at-cursor link and template insertion equals the actual ProseMirror/TipTap result on all '+caretCases.length+' cases.');
  const nativeSel = JSON.parse(readFileSync(nativePath+'.rich-selection','utf8')) as JSONContent[];
  assert.equal(nativeSel.length,selCases.length);
  nativeSel.forEach((doc,i) => assert.deepEqual(JSON.parse(JSON.stringify(webSchema.nodeFromJSON(doc).toJSON())),JSON.parse(JSON.stringify(selCases[i].expected)),'Native selection formatting differs from TipTap: '+selCases[i].name));
  console.log('Native selection formatting equals the actual TipTap toggleMark on all '+selCases.length+' cases.');
  const nativeTables = JSON.parse(readFileSync(nativePath+'.rich-table-edit','utf8')) as JSONContent[];
  assert.equal(nativeTables.length,tableEditCases.length);
  nativeTables.forEach((doc,i) => assert.deepEqual(JSON.parse(JSON.stringify(webSchema.nodeFromJSON(doc).toJSON())),JSON.parse(JSON.stringify(tableEditCases[i].expected)),'Native table edit differs from prosemirror-tables: '+tableEditCases[i].name));
  console.log('Native table editing equals the actual prosemirror-tables commands on all '+tableEditCases.length+' cases.');
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
