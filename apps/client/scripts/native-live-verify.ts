import { verifyNotebookLifecycle } from './native-notebook-vectors';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { identityFromMnemonic } from '../src/sync/identity';
import { decryptRecord } from '../src/sync/engine';
import { decryptMediaChunks } from '../src/crypto/media';
import { docMediaIds } from '../src/editor/doc';
const path = process.env.CHAPTER_NATIVE_OUTPUT; assert(path,'Live native output required');
const output=JSON.parse(readFileSync(path+'.live','utf8')) as {recordId:string;ciphertext:string;mediaId:string;chunks:string[]};
const id=identityFromMnemonic('legal winner thank year wave sausage worth useful legal winner thank yellow');
const body=JSON.parse(Buffer.from(decryptRecord(id.dataKey,output.recordId,Buffer.from(output.ciphertext,'base64'))).toString());
assert.equal(body.unknownFuture,true);
assert.deepEqual(docMediaIds(JSON.parse(body.bodyJson)),[output.mediaId]);
assert.equal(JSON.parse(body.bodyJson).future.keep,true);
assert.deepEqual(Buffer.from(decryptMediaChunks(id.mediaKey,output.mediaId,output.chunks.map(c=>Buffer.from(c,'base64')))),Buffer.alloc((1<<20)+17,77));
console.log('PASS: actual web decoder opens native ciphertext fetched back from real TLS relay/Postgres + fixture media store.');

await verifyNotebookLifecycle(path+'.notebook-live-lifecycle',id.dataKey);
