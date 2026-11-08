// Public BIP39 test phrase only. Never use these identities for real journals.
// --write refreshes committed Swift fixtures; default verifies native-generated
// ciphertext using the ACTUAL web implementation (cross-client reverse leg).
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { wordlist } from '@scure/bip39/wordlists/english.js';
import { xchacha20poly1305 } from '@noble/ciphers/chacha.js';
import { deriveIdentity, signWithDevice, signWithOwner } from '../src/crypto/keys';
import { mnemonicToSeed } from '../src/crypto/mnemonic';
import { decryptRecord } from '../src/sync/engine';
import { decrypt } from '../src/crypto/aead';
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
  const native = JSON.parse(readFileSync(path,'utf8')) as {record:string;media:string};
  assert.equal(Buffer.from(decryptRecord(id.dataKey,recordId,Buffer.from(native.record,'base64'))).toString(),body);
  assert.equal(Buffer.from(decrypt(id.mediaKey,Buffer.from(native.media,'base64'),Buffer.from(`media:${recordId}:0/1`))).toString(),'Public media bytes');
  console.log('Swift → web record/media compatibility passed.');
 }
 console.log('Frozen native protocol/key/signature/wordlist fixture verified.');
}
