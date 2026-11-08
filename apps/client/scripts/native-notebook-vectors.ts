// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decryptRecord, pullEntries } from '../src/sync/engine';
import type { RelayClient } from '../src/sync/relay';
type Wire = {id:string;record:string;clock:number;deleted:boolean};
export async function verifyNotebookLifecycle(path:string,dataKey:Uint8Array) {
 const fixture = JSON.parse(readFileSync(path,'utf8')) as {original:Record<string,unknown>[];deleted:Wire[];restored:Wire[]};
 assert.equal(fixture.original.length,2);assert.equal(fixture.deleted.length,2);assert.equal(fixture.restored.length,2);
 for (const [stage,records] of [['deleted',fixture.deleted],['restored',fixture.restored]] as const) {
  for (const [index,wire] of records.entries()) {
   assert.equal(wire.deleted,stage === 'deleted'); assert.ok(Number.isSafeInteger(wire.clock));
   const body = JSON.parse(Buffer.from(decryptRecord(dataKey,wire.id,Buffer.from(wire.record,'base64'))).toString());
   assert.deepEqual(body,{...fixture.original[index],updatedAt:wire.clock},'Notebook lifecycle must preserve complete original body/opaque fields/media, not rebuild a lossy subset');
   assert.equal(wire.id,fixture.deleted[index].id);
   if(stage === 'restored') assert.ok(wire.clock > fixture.deleted[index].clock);
  }
  // This is the REAL original sync router + journal/entry codecs. Transport is
  // a frozen Swift ciphertext fixture, not a claim of a live HTTP server.
  const transport = {pull:async()=>({entries:records.map(w=>({entry_id:w.id,lww_clock:w.clock,ciphertext:w.record,deleted:w.deleted})),cursor:records.length,more:false})} as unknown as RelayClient;
  const decoded = await pullEntries(transport,'public-fixture-token',dataKey,0);
  assert.equal(decoded.journals.length,1);assert.equal(decoded.entries.length,1);
  assert.equal(decoded.journals[0].id,fixture.original[0].journalId);
  assert.equal(decoded.journals[0].recordId,records[0].id);assert.equal(decoded.journals[0].deleted,stage === 'deleted');
  assert.equal(decoded.entries[0].id,records[1].id);assert.equal(decoded.entries[0].deleted,stage === 'deleted');
  assert.equal(decoded.entries[0].bodyJson,fixture.original[1].bodyJson);assert.deepEqual(decoded.entries[0].labels,fixture.original[1].labels ?? []);
 }
 console.log('PASS Swift notebook cascade/restore → actual original web crypto, sync router and journal/entry codecs; same IDs, full original bodies, media and opaque fields, later restore clocks.');
}
