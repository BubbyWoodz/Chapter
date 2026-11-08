import 'fake-indexeddb/auto';
import { SettingsJournal,type SettingsState } from '../src/appearance/settingsJournal';
import { loadAiSettingsRecord,storeAiSettingsRecord } from '../src/platform/keystore.web';
// Real loopback TLS/Go/Postgres partner. Public test identity only; no service deployment.
import assert from 'node:assert/strict';
import { identityFromMnemonic, authenticate } from '../src/sync/identity';
import { RelayClient } from '../src/sync/relay';
import { pullEntries, pushAiSettings, toPushAiSettings } from '../src/sync/engine';
import { withAppearance, readAppearance } from '../src/appearance/shared';
import { defaultAiSettings } from '../src/ai/types';
const url=process.env.CHAPTER_NATIVE_LIVE_URL;
assert(url && new URL(url).hostname==='localhost' && process.env.GITHUB_ACTIONS==='true');
const relay=new RelayClient(url),identity=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
const session=await authenticate(relay,identity);
let saved:SettingsState={current:null,recovered:[],dirty:false};
const makeJournal=()=>new SettingsJournal(identity.aiKey,{load:()=>loadAiSettingsRecord('live-web'),store:(value,expected)=>storeAiSettingsRecord(value,'live-web',expected)},()=>true,state=>{saved=structuredClone(state)});
let journal=makeJournal();await journal.load();
if(process.argv.includes('--seed')) {
 const settings={...withAppearance(defaultAiSettings(),{v:1,mode:'light',palette:'sea',skin:'forest'}),unknownFuture:{preserve:true}};
 await journal.receive([{recordId:'public-live-appearance',updatedAt:100,settings}]);
 await journal.edit(current=>withAppearance(current,{v:1,mode:'light',palette:'sea',skin:'forest'}),100);
 assert(saved.current);await pushAiSettings(relay,session.token,identity.dataKey,saved.current);
 await journal.acknowledge(saved.current);
 console.log('PASS: actual web codec seeded encrypted shared appearance into real TLS relay/Postgres.');
} else {
 let cursor=0,found=false;
 for(let page=0;page<100;page++) {
   const result=await pullEntries(relay,session.token,identity.dataKey,cursor);cursor=result.cursor;
   for(const record of result.aiSettings) if(record.recordId==='public-live-appearance') {
     assert(record.settings);assert.deepEqual(readAppearance(record.settings.chapterAppearance),{v:1,mode:'dark',palette:'plum',skin:'lavender'});
     assert.equal(record.settings.enabled,false);assert.deepEqual((record.settings as unknown as Record<string,unknown>).unknownFuture,{preserve:true});found=true;
     await journal.receive([record]);
     journal=makeJournal();await journal.load();
     const divergent={...record,settings:{...record.settings,chapterAppearance:{v:1,mode:'light',palette:'rose',skin:'blossom'}}};
     await journal.restore({current:divergent,recovered:[],dirty:true});
     const rejected=await relay.push(session.token,[toPushAiSettings(identity.dataKey,divergent)]);
     assert.equal(rejected.results[0].applied,false,'Actual original relay must reject an equal-clock competing browser write');
     await journal.receive([record]);journal=makeJournal();await journal.load();
     assert(!saved.dirty);assert(saved.recovered.some(r=>JSON.stringify(r.settings?.chapterAppearance)===JSON.stringify(divergent.settings.chapterAppearance)),'Losing browser intent must survive encrypted restart');
     assert.deepEqual(saved.current?.settings?.chapterAppearance,record.settings.chapterAppearance);
     console.log('PASS actual web settings journal + real relay equal-clock rejection: authoritative theme converged, losing configuration retained encrypted across restart.');
     // An original client editing its AI form retains the unknown shared field.
     assert.deepEqual({...record.settings,enabled:false}.chapterAppearance,record.settings.chapterAppearance);
   }
   if(!result.more)break;if(page===99)throw new Error('Unbounded theme pull');
 }
 assert(found,'Native theme must be present in the actual server pull');
 console.log('PASS: actual web pull/decrypt sees native preference, disabled AI and all future fields after native restart/offline/stale-write recovery.');
}
