// Real loopback TLS/Go/Postgres partner. Public test identity only; no service deployment.
import assert from 'node:assert/strict';
import { identityFromMnemonic, authenticate } from '../src/sync/identity';
import { RelayClient } from '../src/sync/relay';
import { pullEntries, pushAiSettings } from '../src/sync/engine';
import { withAppearance, readAppearance } from '../src/appearance/shared';
import { defaultAiSettings } from '../src/ai/types';
const url=process.env.CHAPTER_NATIVE_LIVE_URL;
assert(url && new URL(url).hostname==='localhost' && process.env.GITHUB_ACTIONS==='true');
const relay=new RelayClient(url),identity=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
const session=await authenticate(relay,identity);
if(process.argv.includes('--seed')) {
 const settings={...withAppearance(defaultAiSettings(),{v:1,mode:'light',palette:'sea',skin:'forest'}),unknownFuture:{preserve:true}};
 await pushAiSettings(relay,session.token,identity.dataKey,{recordId:'public-live-appearance',updatedAt:100,settings});
 console.log('PASS: actual web codec seeded encrypted shared appearance into real TLS relay/Postgres.');
} else {
 let cursor=0,found=false;
 for(let page=0;page<100;page++) {
   const result=await pullEntries(relay,session.token,identity.dataKey,cursor);cursor=result.cursor;
   for(const record of result.aiSettings) if(record.recordId==='public-live-appearance') {
     assert(record.settings);assert.deepEqual(readAppearance(record.settings.chapterAppearance),{v:1,mode:'dark',palette:'plum',skin:'lavender'});
     assert.equal(record.settings.enabled,false);assert.deepEqual((record.settings as unknown as Record<string,unknown>).unknownFuture,{preserve:true});found=true;
     // An original client editing its AI form retains the unknown shared field.
     assert.deepEqual({...record.settings,enabled:false}.chapterAppearance,record.settings.chapterAppearance);
   }
   if(!result.more)break;if(page===99)throw new Error('Unbounded theme pull');
 }
 assert(found,'Native theme must be present in the actual server pull');
 console.log('PASS: actual web pull/decrypt sees native preference, disabled AI and all future fields after native restart/offline/stale-write recovery.');
}
