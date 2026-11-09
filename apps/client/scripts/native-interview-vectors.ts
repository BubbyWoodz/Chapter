// SPDX-License-Identifier: AGPL-3.0-or-later
// Interview types: the native manager ports the web InterviewTypesSheet
// (createInterviewType / updateInterviewType / deleteInterviewType via mutateSeeded).
// The built-in seeds and the exact wire bodies come from the real web modules.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { BUILTIN_INTERVIEWS } from '../src/data/interviews';
import { toPushInterviewType, decryptRecord, type InterviewType } from '../src/sync/engine';

const key = new Uint8Array(32).fill(9);
const body = (t: InterviewType) => { const p = toPushInterviewType(key, t); return { entry_id: p.entry_id, lww_clock: p.lww_clock, deleted: p.deleted, body: JSON.parse(Buffer.from(decryptRecord(key, p.entry_id, Buffer.from(p.ciphertext, 'base64'))).toString('utf8')) }; };

export function verifyInterviews(write: boolean): void {
  const builtins = BUILTIN_INTERVIEWS.map((b) => ({ slug: b.slug, nameKey: b.nameKey, introKey: b.introKey, prompt: b.prompt }));
  const created: InterviewType = { id: 'a'.repeat(32), name: 'Evening', intro: 'One line', prompt: 'Cover the evening.', createdAt: 1700000000000, updatedAt: 1700000000000 };
  const fork: InterviewType = { id: 'b'.repeat(32), name: 'Mine', intro: 'Intro', prompt: BUILTIN_INTERVIEWS[0].prompt, builtin: BUILTIN_INTERVIEWS[0].slug, createdAt: 1700000000001, updatedAt: 1700000000001 };
  const tomb: InterviewType = { ...created, updatedAt: 1700000000002, deleted: true };
  const fixture = { builtins, wire: { created: body(created), fork: body(fork), tombstone: body(tomb) } };
  const resURL = new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/builtin-interviews.json', import.meta.url);
  const vecURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/interview-types.json', import.meta.url);
  if (write) { writeFileSync(resURL, JSON.stringify(builtins) + '\n'); writeFileSync(vecURL, JSON.stringify(fixture, null, 1) + '\n'); }
  else {
    assert.deepEqual(JSON.parse(readFileSync(resURL, 'utf8')), builtins, 'Native built-in interviews must equal the web BUILTIN_INTERVIEWS');
    assert.deepEqual(JSON.parse(readFileSync(vecURL, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native interview-type wire vectors must equal the web codec');
  }
  console.log(`Native interview types equal the web (${builtins.length} built-ins, create/fork/tombstone wire bodies).`);
}
