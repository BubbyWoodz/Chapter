import { verifyNotebookLifecycle } from './native-notebook-vectors';
import { verifyThemeCatalog } from './native-theme-vectors';
// Public BIP39 test phrase only. Never use these identities for real journals.
// --write refreshes committed Swift fixtures; default verifies native-generated
// ciphertext using the ACTUAL web implementation (cross-client reverse leg).
import assert from 'node:assert/strict';
import { verifyRichFixture } from './native-rich-vectors';
import { verifyLocalizedBuiltins } from './native-locale-vectors';
import { verifyMath } from './native-math-vectors';
import { verifyUIStrings } from './native-ui-strings-vectors';
import { verifyStats } from './native-stats-vectors';
import { verifySearch } from './native-search-vectors';
import { verifyBadges } from './native-badges-vectors';
import { verifyInterviews } from './native-interview-vectors';
import { verifyExport } from './native-export-vectors';
import { verifyMarkdown } from './native-markdown-vectors';
import { verifyDayOne } from './native-dayone-vectors';
import { verifyZip } from './native-zip-vectors';
import { verifyDayOneArchive } from './native-dayone-archive-vectors';
import { verifyDayOneImport } from './native-dayone-import-vectors';
import { readFileSync, writeFileSync } from 'node:fs';
import { wordlist } from '@scure/bip39/wordlists/english.js';
import { ed25519 } from '@noble/curves/ed25519.js';
import { xchacha20poly1305 } from '@noble/ciphers/chacha.js';
import { deriveIdentity, signWithDevice, signWithOwner } from '../src/crypto/keys';
import { mnemonicToSeed } from '../src/crypto/mnemonic';
import { decryptRecord } from '../src/sync/engine';
import { decrypt } from '../src/crypto/aead';
import { decryptMediaChunks } from '../src/crypto/media';
import { docMediaIds, docToText } from '../src/editor/doc';
verifyThemeCatalog();
const phrase = 'legal winner thank year wave sausage worth useful legal winner thank yellow';
const seed = mnemonicToSeed(phrase), id = deriveIdentity(seed);
const recordId = '0123456789abcdef0123456789abcdef';
const body = JSON.stringify({journalId:'notebook', title:'Public test 📝',bodyText:'Offline interop',bodyJson:'{"type":"doc","content":[]}',labels:['test'],createdAt:1700000000000,updatedAt:1700000000001,unknownFuture:{preserve:true}});
const aad = new TextEncoder().encode(`mneme:record:v1:${recordId}`);
const nonce = new Uint8Array(24).fill(7);
const envelope = (plain: Uint8Array, key: Uint8Array, aad?: Uint8Array) => Buffer.concat([Buffer.from([1]),nonce, xchacha20poly1305(key,nonce,aad).encrypt(plain)]).toString('base64');
const registrationMessage = Buffer.concat([Buffer.from('mneme:register:'),id.ownerPub,id.devicePub]);
const bindMessage = Buffer.concat([Buffer.from('mneme:bind-device:v1:'),id.ownerPub,id.ownerSignPub,id.devicePub]);
const fixture = { phrase, seed:Buffer.from(seed).toString('hex'), dataKey:Buffer.from(id.dataKey).toString('hex'),mediaKey:Buffer.from(id.mediaKey).toString('hex'),ownerId:id.ownerId,ownerPublic:Buffer.from(id.ownerPub).toString('hex'),ownerSigningPublic:Buffer.from(id.ownerSignPub).toString('hex'),devicePublic:Buffer.from(id.devicePub).toString('hex'),signature:Buffer.from(signWithDevice(id.devicePriv,registrationMessage)).toString('base64'),ownerSignature:Buffer.from(signWithOwner(id.ownerSignPriv,bindMessage)).toString('base64'),recordId,body,record:envelope(Buffer.from(body),id.dataKey,aad),legacy:envelope(Buffer.from(body),id.dataKey),media:envelope(Buffer.from('Public media bytes'),id.mediaKey,Buffer.from(`media:${recordId}:0/1`))};
const fixturePath = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/web-v1.json', import.meta.url);
if(process.argv.includes('--write')) {
 writeFileSync(fixturePath, JSON.stringify(fixture,null,2)+'\n');
 writeFileSync(new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/english.json',import.meta.url),JSON.stringify(wordlist)+'\n');
} else {
 assert.deepEqual(JSON.parse(readFileSync(fixturePath,'utf8')), fixture, 'Frozen native fixture drifted');
 assert.deepEqual(JSON.parse(readFileSync(new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/english.json',import.meta.url),'utf8')),wordlist);
 const path = process.env.CHAPTER_NATIVE_OUTPUT;
 if(path) {
  const native = JSON.parse(readFileSync(path,'utf8')) as {record:string;media:string;registration:Record<string,string>;challenge:string;challengeSignature:string};
  assert.equal(Buffer.from(decryptRecord(id.dataKey,recordId,Buffer.from(native.record,'base64'))).toString(),body);
  assert.equal(Buffer.from(decrypt(id.mediaKey,Buffer.from(native.media,'base64'),Buffer.from(`media:${recordId}:0/1`))).toString(),'Public media bytes');
  const uploaded = JSON.parse(readFileSync(path + '.media-upload','utf8')) as {id:string;chunks:string[];plainBytes:number;cipherBytes:number;recordId:string;record:string};
  const chunks = uploaded.chunks.map(c => Buffer.from(c,'base64'));
  assert.equal(chunks.length,3);
  assert.equal(uploaded.cipherBytes,uploaded.plainBytes + 41 * chunks.length);
  assert.equal(chunks.reduce((n,c)=>n+c.length,0),uploaded.cipherBytes);
  const expectedMedia = Buffer.from(Array.from({length:2*(1<<20)+17},(_,i)=>(i*31+7)%256));
  assert.deepEqual(Buffer.from(decryptMediaChunks(id.mediaKey,uploaded.id,chunks)),expectedMedia);
  assert.throws(()=>decryptMediaChunks(id.mediaKey,uploaded.id,[chunks[1],chunks[0],chunks[2]]));
  assert.throws(()=>decryptMediaChunks(id.mediaKey,uploaded.id,chunks.slice(0,2)));
  const attachedBody = JSON.parse(Buffer.from(decryptRecord(id.dataKey,uploaded.recordId,Buffer.from(uploaded.record,'base64'))).toString());
  const attachedDoc = JSON.parse(attachedBody.bodyJson);
  assert.deepEqual(docMediaIds(attachedDoc),[uploaded.id]);
  assert.equal(attachedBody.bodyText,docToText(attachedDoc));
  assert.deepEqual(attachedBody.unknownFuture,JSON.parse(body).unknownFuture);
  assert.deepEqual(attachedDoc.content[0].attrs,{id:uploaded.id,kind:'file',mime:'application/octet-stream',name:'PRIVATE-FILENAME',bytes:uploaded.plainBytes});
  console.log('Swift durable media stage → actual web chunk decoder: multi-chunk payload, framing totals, reorder/truncation rejection passed.');
  const notebook = JSON.parse(readFileSync(path + '.notebook','utf8')) as {id:string;ciphertext:string;expected:Record<string,unknown>};
  const notebookBody = JSON.parse(Buffer.from(decryptRecord(id.dataKey,notebook.id,Buffer.from(notebook.ciphertext,'base64'))).toString());
  assert.deepEqual(notebookBody,notebook.expected);
  assert.equal(notebookBody.kind,'journal'); assert.equal(notebookBody.journalId,'public-logical-notebook');
  assert.equal(notebookBody.name,'Renamed 📝'); assert.equal(notebookBody.subtitle,'New subtitle');
  assert.equal(notebookBody.color,'#B0563A'); assert.equal(notebookBody.cover,'grid');
  assert.deepEqual(notebookBody.opaqueFuture,{keep:[true,7]}); assert.equal(notebookBody.createdAt,1);
  console.log('Swift notebook metadata edit → actual web record decoder: all fields, stable IDs and opaque data passed.');
  const r = native.registration;
  assert.equal(r.owner_pubkey, Buffer.from(id.ownerPub).toString('base64'));
  assert.equal(r.device_pubkey, Buffer.from(id.devicePub).toString('base64'));
  assert.equal(r.owner_sign_pubkey, Buffer.from(id.ownerSignPub).toString('base64'));
  assert(ed25519.verify(Buffer.from(r.signature,'base64'), registrationMessage, id.devicePub));
  assert(ed25519.verify(Buffer.from(r.owner_signature,'base64'), bindMessage, id.ownerSignPub));
  assert.equal(Buffer.from(native.challenge,'base64').length,32);
  assert(ed25519.verify(Buffer.from(native.challengeSignature,'base64'),Buffer.from(native.challenge,'base64'),id.devicePub));
  console.log('Swift → web record/media and registration/challenge signature compatibility passed.');
 }
 console.log('Frozen native protocol/key/signature/wordlist fixture verified.');
}

verifyRichFixture(process.argv.includes('--write'), id, process.env.CHAPTER_NATIVE_OUTPUT);
await verifyLocalizedBuiltins(process.argv.includes('--write'));
verifyMath(process.argv.includes('--write'));
await verifyUIStrings(process.argv.includes('--write'));
verifyStats(process.argv.includes('--write'));
await verifySearch(process.argv.includes('--write'));
verifyBadges(process.argv.includes('--write'));
verifyInterviews(process.argv.includes('--write'));
verifyMarkdown(process.argv.includes('--write'));
verifyDayOne(process.argv.includes('--write'));
verifyZip(process.argv.includes('--write'));
verifyDayOneArchive(process.argv.includes('--write'));
await verifyDayOneImport(process.argv.includes('--write'));
await verifyExport(process.argv.includes('--write'));

if (process.env.CHAPTER_NATIVE_OUTPUT) await verifyNotebookLifecycle(process.env.CHAPTER_NATIVE_OUTPUT+'.notebook-lifecycle',id.dataKey);
