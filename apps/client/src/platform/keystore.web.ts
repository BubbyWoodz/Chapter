// The browser (PWA) keystore backend. What the PWA persists outside the per-owner
// OPFS database: the optional Argon2id/PRF-sealed seed (§6 at-rest) and the
// seed-key-sealed AI settings. IndexedDB rather than localStorage because the
// records carry binary fields and IDB is async.
//
// Selected by keystore.ts when not running under Tauri. The Tauri backend
// (keystore.tauri.ts, Track B) stores the same records in OS secure storage.
import { isSealedSeed, type SealedSeed } from '../crypto/seedlock';
import { SettingsWriteConflict, type SealedAiSettings } from '../ai/settings';

const DB_NAME = 'mneme-keystore';
const STORE = 'kv';
const KEY = 'sealed-seed';
const AI_KEY = 'ai-settings';

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('indexeddb unavailable'));
  });
}

async function run<T>(mode: IDBTransactionMode, op: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await openDb();
  try {
    return await new Promise<T>((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      let result: T;
      // Request success is NOT durable success: a transaction may abort later.
      tx.oncomplete = () => resolve(result);
      tx.onabort = () => reject(tx.error ?? new Error('keystore transaction aborted'));
      tx.onerror = () => reject(tx.error ?? new Error('keystore transaction failed'));
      const req = op(tx.objectStore(STORE));
      req.onsuccess = () => { result=req.result; };
      req.onerror = () => reject(req.error ?? new Error('keystore operation failed'));
    });
  } finally {
    db.close();
  }
}

/** null when nothing is stored or IndexedDB is unavailable (private mode, Node). */
export async function loadSealedSeed(): Promise<SealedSeed | null> {
  if (typeof indexedDB === 'undefined') return null;
  try {
    const rec = (await run('readonly', (s) => s.get(KEY))) as SealedSeed | undefined;
    return rec && isSealedSeed(rec) ? rec : null;
  } catch {
    return null;
  }
}

/** Throws when persistence fails — callers degrade to the nothing-stored mode. */
export async function storeSealedSeed(record: SealedSeed): Promise<void> {
  await run('readwrite', (s) => s.put(record, KEY));
}

export async function clearSealedSeed(): Promise<void> {
  if (typeof indexedDB === 'undefined') return;
  try {
    await run('readwrite', (s) => s.delete(KEY));
  } catch {
    /* nothing stored / no IDB — locked-out is the safe default */
  }
}

/** null when nothing is stored or IndexedDB is unavailable. */
export async function loadAiSettingsRecord(namespace?: string): Promise<SealedAiSettings | null> {
  if (typeof indexedDB === 'undefined') return null;
  try {
    const rec = (await run('readonly', (s) => s.get(namespace ? AI_KEY+':'+namespace : AI_KEY))) as SealedAiSettings | undefined;
    if(rec) { if(rec.v!==1)throw new Error('Unsupported saved settings');return rec; }
    if(namespace) { const legacy=await run('readonly',s=>s.get(AI_KEY)) as SealedAiSettings|undefined;return legacy ? {...legacy,legacy:true}:null; }
    return null;
  } catch(error) { throw error; }
}

/** Throws when persistence fails — callers degrade to the not-configured mode. */
export async function storeAiSettingsRecord(record: SealedAiSettings, namespace?: string, expected?:SealedAiSettings|null): Promise<void> {
  if(expected===undefined){await run('readwrite',s=>s.put(record,namespace?AI_KEY+':'+namespace:AI_KEY));return}
  const db=await openDb();
  try { await new Promise<void>((resolve,reject)=>{
    const tx=db.transaction(STORE,'readwrite'),store=tx.objectStore(STORE);
    let conflict:Error|undefined;
    tx.oncomplete=()=>resolve();tx.onabort=()=>reject(conflict??tx.error??new Error('Settings transaction aborted'));tx.onerror=()=>reject(tx.error??new Error('Settings transaction failed'));
    const plain=(seal:SealedAiSettings|undefined|null)=>{if(!seal)return null;const {legacy:_,...value}=seal;return JSON.stringify(value)};
    const request=store.get(namespace?AI_KEY+':'+namespace:AI_KEY);
    request.onsuccess=()=>{
      if(plain(request.result)!==plain(expected?.legacy?null:expected)){conflict=new SettingsWriteConflict();tx.abort();return}
      store.put(record,namespace?AI_KEY+':'+namespace:AI_KEY);
      // Legacy is retained until an explicit owning-vault lifecycle cleanup.
      // New per-owner writes never erase another vault's only old-format copy.
    };
  }); } finally {db.close()}
}

export async function clearAiSettingsRecord(namespace?: string, legacyExpected?:SealedAiSettings): Promise<void> {
  if(typeof indexedDB==='undefined')return;
  if(!namespace){await run('readwrite',s=>s.delete(AI_KEY));return}
  const db=await openDb();
  try {await new Promise<void>((resolve,reject)=>{
    const tx=db.transaction(STORE,'readwrite'),store=tx.objectStore(STORE);
    tx.oncomplete=()=>resolve();tx.onabort=()=>reject(tx.error??new Error('Settings cleanup aborted'));tx.onerror=()=>reject(tx.error??new Error('Settings cleanup failed'));
    store.delete(AI_KEY+':'+namespace);
    if(legacyExpected){const request=store.get(AI_KEY);request.onsuccess=()=>{if(JSON.stringify(request.result)===JSON.stringify(legacyExpected))store.delete(AI_KEY)}}
  });}finally{db.close()}
}
