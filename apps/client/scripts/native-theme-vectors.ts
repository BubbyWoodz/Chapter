// Generated ONLY from original web tokens/defaults. Public fixtures, no secrets.
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { PALETTES, SKINS } from '../src/hooks/useTheme';
import { defaultAiSettings } from '../src/ai/types';
import { identityFromMnemonic } from '../src/sync/identity';
import { toPushAiSettings, decryptRecord } from '../src/sync/engine';
const css=readFileSync(new URL('../src/styles/tokens.css',import.meta.url),'utf8').replace(/\/\*[\s\S]*?\*\//g,'');
const blocks=new Map([...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m=>[m[1].trim(),Object.fromEntries([...m[2].matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)].map(x=>[x[1],x[2].trim()]))]));
const skins=Object.fromEntries(SKINS.map(s=>[s.id,{defaultAccent:s.accent,...Object.fromEntries(['light','dark'].map(mode=>{
const all={...blocks.get(':root'),...(mode==='dark'?blocks.get("[data-theme='dark']"):{}),...blocks.get(`[data-skin='${s.id}']`),...(mode==='dark'?blocks.get(`[data-skin='${s.id}'][data-theme='dark']`):{})};
const tokens=Object.fromEntries(['paper','surface','surface-2','ink','ink-2','ink-3','line'].map(k=>{assert.match(all[k],/^#[0-9a-f]{6}$/i);return[k,all[k]]})); return[mode,tokens];}))}]));
const defaults=defaultAiSettings();delete defaults.transcription;
const catalog={v:1,palettes:Object.fromEntries(PALETTES.map(p=>[p.id,p.accent])),skins,defaultSettings:defaults};
const path=new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/appearance-v1.json',import.meta.url);
const identity=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
const fixturePath=new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/web-theme-v1.json',import.meta.url);
const settings={...defaults,chapterAppearance:{v:1,mode:'light',palette:'sea',skin:'forest'},unknownFuture:{preserve:true}};
export function verifyThemeCatalog():void {
 if(process.argv.includes('--write')) {
   const wire=toPushAiSettings(identity.dataKey,{recordId:'public-shared-appearance',updatedAt:100,settings});
   writeFileSync(fixturePath,JSON.stringify(wire,null,2)+'\n');
 }
 const fixture=JSON.parse(readFileSync(fixturePath,'utf8'));
 const opened=JSON.parse(Buffer.from(decryptRecord(identity.dataKey,fixture.entry_id,Buffer.from(fixture.ciphertext,'base64'))).toString());
 assert.deepEqual(opened.settings,settings);

 if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(catalog,null,2)+'\n');
 assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),catalog,'Native colors/defaults must match actual original CSS and palettes');
 if(process.env.CHAPTER_NATIVE_OUTPUT) {
 const data=JSON.parse(readFileSync(process.env.CHAPTER_NATIVE_OUTPUT+'.theme','utf8')) as {id:string;ciphertext:string;expected:unknown};
 const identity=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
 const body=JSON.parse(Buffer.from(decryptRecord(identity.dataKey,data.id,Buffer.from(data.ciphertext,'base64'))).toString());
 assert.equal(body.kind,'aiSettings');
 assert.deepEqual(body.settings.chapterAppearance,{v:1,mode:'dark',palette:'plum',skin:'lavender'});
 assert.equal(body.settings.enabled,false);assert.deepEqual(body.settings.unknownFuture,{preserve:true});
 assert.deepEqual(body,data.expected);
 console.log('PASS: native shared appearance opens in actual original web settings codec, all opaque/AI fields preserved.');
 }
}
if(process.argv[1]?.endsWith('native-theme-vectors.ts'))verifyThemeCatalog();
