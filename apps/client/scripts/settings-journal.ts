// Real production coordinator + crypto + browser adapter, standards-based test IDB.
// Faults are injected; this is not a physical-browser power-loss certification.
import 'fake-indexeddb/auto';
import assert from 'node:assert/strict';
import { SettingsJournal,type SettingsState } from '../src/appearance/settingsJournal';
import { withAppearance,withAiSettingsPreservingAppearance } from '../src/appearance/shared';
import { defaultAiSettings } from '../src/ai/types';
import { sealAiSettings,openAiSettings,SettingsWriteConflict } from '../src/ai/settings';
import { loadAiSettingsRecord,storeAiSettingsRecord } from '../src/platform/keystore.web';
import { identityFromMnemonic } from '../src/sync/identity';
import { pushAiSettings,toPushAiSettings,decryptRecord } from '../src/sync/engine';
const identity=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
const initial={...defaultAiSettings(),anthropic:{apiKey:'PUBLIC-RECOVERY-KEY',model:'future-model'},future:{keep:true},chapterAppearance:{v:1,mode:'light',palette:'sea',skin:'forest'}};
const choice={v:1 as const,mode:'dark' as const,palette:'plum',skin:'lavender'};
function setup(scope:string,alive=()=>true,hook?:()=>Promise<void>) {
 let state:SettingsState={current:null,recovered:[],dirty:false};
 const disk={load:()=>loadAiSettingsRecord(scope),store:async(value:Parameters<typeof storeAiSettingsRecord>[0],expected:Parameters<typeof storeAiSettingsRecord>[2])=>{await hook?.();await storeAiSettingsRecord(value,scope,expected)}};
 const journal=new SettingsJournal(identity.aiKey,disk,alive,value=>{state=structuredClone(value)});
 return {journal,get state(){return state}};
}
// Legacy v1 is copied transactionally into the owner slot, including original key.
const legacy=sealAiSettings(identity.aiKey,initial,{recordId:'canonical',updatedAt:100,dirty:false});await storeAiSettingsRecord(legacy);
const a=setup('owner-a');await a.journal.load();assert.equal(a.state.current?.settings?.anthropic.apiKey,'PUBLIC-RECOVERY-KEY');assert.deepEqual(await loadAiSettingsRecord(),legacy,'A verified legacy copy is retained until owning-vault lifecycle cleanup');
assert.deepEqual(openAiSettings(identity.aiKey,(await loadAiSettingsRecord('owner-a'))!),initial);
const {clearAiSettingsRecord}=await import('../src/platform/keystore.web');await clearAiSettingsRecord();
// A request can succeed but its transaction still abort. Never publish a save.
const prior=await loadAiSettingsRecord('owner-a'),before=structuredClone(a.state),put=IDBObjectStore.prototype.put;
IDBObjectStore.prototype.put=function(this:IDBObjectStore,...args:Parameters<IDBObjectStore['put']>){const req=put.apply(this,args);req.addEventListener('success',()=>this.transaction.abort());return req};
await assert.rejects(a.journal.edit(current=>withAppearance(current,choice),101));
IDBObjectStore.prototype.put=put;assert.deepEqual(a.state,before);assert.deepEqual(await loadAiSettingsRecord('owner-a'),prior);
await a.journal.edit(current=>withAppearance(current,choice),101);const sent=structuredClone(a.state.current!);
// In-flight old acknowledgments cannot clear a newer durable edit.
await a.journal.edit(current=>withAppearance(current,{...choice,palette:'rose'}),101);
await a.journal.acknowledge(sent);assert(a.state.dirty);assert.equal(a.state.current?.updatedAt,102);
// Original server-authoritative equal-clock response wins, losing dirty intent remains encrypted.
const losing=structuredClone(a.state.current!);
const remote={...losing,settings:{...initial,anthropic:{apiKey:'PUBLIC-NEW-CREDENTIAL',model:'future-model'},chapterAppearance:{v:1,mode:'light',palette:'moss',skin:'forest'}}};
await a.journal.receive([remote]);assert(!a.state.dirty);assert.equal(a.state.current?.settings?.anthropic.apiKey,'PUBLIC-NEW-CREDENTIAL');assert(a.state.recovered.some(row=>row.settings?.chapterAppearance&&JSON.stringify(row.settings.chapterAppearance)===JSON.stringify(losing.settings?.chapterAppearance)));
const reopened=setup('owner-a');await reopened.journal.load();assert.deepEqual(reopened.state,a.state);
const seal=(await loadAiSettingsRecord('owner-a'))!;assert(seal.recovered?.length);assert(!JSON.stringify(seal).includes('PUBLIC-RECOVERY-KEY'));assert(!JSON.stringify(seal).includes('PUBLIC-NEW-CREDENTIAL'));
// Explicit theme restore preserves current credential and archives the current version.
await reopened.journal.edit(current=>withAppearance(current,choice),200,true);assert.equal(reopened.state.current?.settings?.anthropic.apiKey,'PUBLIC-NEW-CREDENTIAL');assert(reopened.state.recovered.length>=2);
const wire=toPushAiSettings(identity.dataKey,reopened.state.current!);const body=JSON.parse(Buffer.from(decryptRecord(identity.dataKey,wire.entry_id,Buffer.from(wire.ciphertext,'base64'))).toString());assert.deepEqual(body.settings.chapterAppearance,choice);assert.deepEqual(body.settings.future,{keep:true});
// Clear credentials without losing shared theme; restart restores durable outbox.
await reopened.journal.edit(current=>withAiSettingsPreservingAppearance(current,null),201);assert.equal(reopened.state.current?.settings?.anthropic.apiKey,'');assert.equal(reopened.state.current?.settings?.enabled,false);
const offline=setup('owner-a');await offline.journal.load();assert(offline.state.dirty);assert.deepEqual(offline.state.current,reopened.state.current);
// A true settings tombstone remains durable across restart, not deleted from disk.
const empty=setup('owner-empty');await empty.journal.load();await empty.journal.edit(()=>null,300);const deleted=setup('owner-empty');await deleted.journal.load();assert(deleted.state.current?.deleted);assert.equal(deleted.state.current.settings,null);assert(deleted.state.dirty);
// Cross-tab CAS refuses stale writes; explicit reload preserves displaced dirty data.
const tab1=setup('tabs'),tab2=setup('tabs');await tab1.journal.load();await tab2.journal.load();await tab1.journal.edit(()=>initial,400);
await assert.rejects(tab2.journal.edit(()=>({...initial,enabled:true}),400),SettingsWriteConflict);
assert.equal(tab2.state.current,null);await tab2.journal.load();assert.equal(tab2.journal.snapshot().current?.updatedAt,400);
await tab2.journal.edit(current=>withAppearance(current,choice),401);
await assert.rejects(tab1.journal.acknowledge(tab1.state.current!),SettingsWriteConflict);
await tab1.journal.load();assert.equal(tab1.state.current?.updatedAt,401);assert(tab1.state.recovered.some(r=>r.updatedAt===400));
// Queued remote receive cannot overtake a pending durable edit or drop its key.
let release!:()=>void,started!:()=>void;const gate=new Promise<void>(r=>{release=r}),entered=new Promise<void>(r=>{started=r});let hold=false;
const concurrent=setup('concurrent',()=>true,async()=>{if(hold){hold=false;started();await gate}});await concurrent.journal.load();await concurrent.journal.edit(()=>initial,500);
hold=true;const edit=concurrent.journal.edit(current=>withAppearance(current,choice),501);await entered;
const receive=concurrent.journal.receive([{recordId:concurrent.state.current!.recordId,updatedAt:502,settings:{...initial,anthropic:{apiKey:'PUBLIC-CONCURRENT',model:'future'}}}]);release();await edit;await receive;
assert.equal(concurrent.state.current?.settings?.anthropic.apiKey,'PUBLIC-CONCURRENT');assert(concurrent.state.recovered.some(r=>r.updatedAt===501));
// Lock during a pending write cannot republish plaintext or run queued edits.
let alive=true,unlock!:()=>void,began!:()=>void;const wait=new Promise<void>(r=>{unlock=r}),pending=new Promise<void>(r=>{began=r});let block=false;
const locking=setup('locking',()=>alive,async()=>{if(block){began();await wait}});await locking.journal.load();block=true;const saving=locking.journal.edit(()=>initial,600);await pending;alive=false;locking.journal.close();unlock();await assert.rejects(saving);assert.equal(locking.state.current,null);await assert.rejects(locking.journal.edit(()=>initial,601));
// Rotation copies all encrypted recoveries to new original-format key; old copy stays on failure.
const checkpoint=tab1.journal.snapshot();const oldBytes=await loadAiSettingsRecord('tabs');
const newKey=new Uint8Array(32).fill(9);let migrated:SettingsState|undefined;
const rotation=new SettingsJournal(newKey,{load:()=>loadAiSettingsRecord('rotated'),store:(value,expected)=>storeAiSettingsRecord(value,'rotated',expected)},()=>true,value=>{migrated=value});
await rotation.restore({...checkpoint,dirty:false});assert(migrated);assert.deepEqual(migrated.recovered,checkpoint.recovered);assert.deepEqual(await loadAiSettingsRecord('tabs'),oldBytes);const rotatedSeal=(await loadAiSettingsRecord('rotated'))!;assert.throws(()=>openAiSettings(identity.aiKey,rotatedSeal));assert.deepEqual(openAiSettings(newKey,rotatedSeal),checkpoint.current?.settings);
const blocked=new SettingsJournal(newKey,{load:()=>loadAiSettingsRecord('rotated'),store:(value,expected)=>storeAiSettingsRecord(value,'rotated',expected)},()=>true,()=>{});await assert.rejects(blocked.restore(checkpoint),SettingsWriteConflict);assert.deepEqual(await loadAiSettingsRecord('tabs'),oldBytes);
// The ORIGINAL push helper previously retired a stale rejection as if applied.
// A newer remote clock must not erase that unacknowledged local edit.
const rejected=setup('stale-server');await rejected.journal.load();await rejected.journal.edit(()=>initial,700);
const makeRelay=(results:unknown)=>({push:async()=>({results})}) as unknown as Parameters<typeof pushAiSettings>[0];
const queued=rejected.state.current!;
assert.equal(await pushAiSettings(makeRelay([{entry_id:queued.recordId,applied:false}]),'PUBLIC',identity.dataKey,queued),false);
for(const results of [[],[{entry_id:'foreign',applied:true}],[{entry_id:queued.recordId,applied:'yes'}],[{entry_id:queued.recordId,applied:true},{entry_id:queued.recordId,applied:true}]])await assert.rejects(pushAiSettings(makeRelay(results),'PUBLIC',identity.dataKey,queued));
assert(rejected.state.dirty);await rejected.journal.receive([{...queued,updatedAt:701,settings:{...initial,enabled:true}}]);
assert(rejected.state.recovered.some(row=>row.updatedAt===700));const rejectedRestart=setup('stale-server');await rejectedRestart.journal.load();assert.deepEqual(rejectedRestart.state,rejected.state);
assert.equal(await pushAiSettings(makeRelay([{entry_id:queued.recordId,applied:true}]),'PUBLIC',identity.dataKey,queued),true);
// A legacy authenticated future payload or malformed sync clock is NOT a foreign vault.
const futureLegacy=sealAiSettings(identity.aiKey,{...initial,v:2} as unknown as Parameters<typeof sealAiSettings>[1]);
await storeAiSettingsRecord(futureLegacy);await assert.rejects(setup('future-legacy').journal.load(),/unsupported ai-settings version/);assert.deepEqual(await loadAiSettingsRecord(),futureLegacy);
const badMeta=sealAiSettings(identity.aiKey,initial,{recordId:'bad-clock',updatedAt:Number.MAX_SAFE_INTEGER+1,dirty:true});
await storeAiSettingsRecord(badMeta);await assert.rejects(setup('bad-legacy-meta').journal.load(),/Invalid settings clock/);assert.deepEqual(await loadAiSettingsRecord(),badMeta);await clearAiSettingsRecord();
console.log('PASS actual settings journal + original crypto + IDB adapter: transaction abort, serial save/pull/ack, equal-clock encrypted recovery/restart, offline tombstone, cross-tab CAS/reload, lock and rekeyed recovery preservation.');
