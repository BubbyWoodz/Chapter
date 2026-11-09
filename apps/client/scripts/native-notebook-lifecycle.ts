// SPDX-License-Identifier: AGPL-3.0-or-later
// Regression for actual original web crypto/router and strict vector verifier.
// Native-generated and genuine-live-server ciphertext are separate CI gates.
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { identityFromMnemonic } from '../src/sync/identity';
import { encrypt } from '../src/crypto/aead';
import { verifyNotebookLifecycle } from './native-notebook-vectors';
const identity=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
const root=mkdtempSync(join(tmpdir(),'chapter-notebook-codec-')),file=join(root,'vectors.json');
const original=[{kind:'journal',journalId:'original',name:'Original',color:'#4E8B85',cover:'lines',opaque:{keep:true}},{journalId:'original',title:'Original rich entry',bodyJson:'{"type":"doc","future":{"keep":true},"content":[]}',bodyText:'',labels:['travel, friends'],attachments:[{id:'a'.repeat(32),mime:'text/plain',bytes:1}],opaque:{keep:['all',true]}}];
const wire=(body:Record<string,unknown>,id:string,clock:number,deleted:boolean)=>({id,clock,deleted,record:Buffer.from(encrypt(identity.dataKey,Buffer.from(JSON.stringify({...body,updatedAt:clock})),Buffer.from('mneme:record:v1:'+id))).toString('base64')});
const fixture={original,deleted:original.map((b,i)=>wire(b,'original-'+i,2,true)),restored:original.map((b,i)=>wire(b,'original-'+i,3,false))};
try {
 writeFileSync(file,JSON.stringify(fixture));await verifyNotebookLifecycle(file,identity.dataKey);
 const wrongFlag=structuredClone(fixture);wrongFlag.deleted[1].deleted=false;writeFileSync(file,JSON.stringify(wrongFlag));await assert.rejects(()=>verifyNotebookLifecycle(file,identity.dataKey));
 const erased=structuredClone(fixture);erased.restored[1]=wire({...original[1],opaque:{}},'original-1',3,false);writeFileSync(file,JSON.stringify(erased));await assert.rejects(()=>verifyNotebookLifecycle(file,identity.dataKey));
 const rollback=structuredClone(fixture);rollback.restored[0]=wire(original[0],'original-0',2,false);writeFileSync(file,JSON.stringify(rollback));await assert.rejects(()=>verifyNotebookLifecycle(file,identity.dataKey));
 console.log('PASS notebook lifecycle vector validation rejects wrong tombstone flag, opaque-field loss and stale restoration clock. Native/real-live outputs remain mandatory separately.');
} finally {rmSync(root,{recursive:true,force:true})}
