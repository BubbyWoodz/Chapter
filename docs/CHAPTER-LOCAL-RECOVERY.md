# Native local writing and deletion recovery

This is additive native preview behavior, not a server/encryption redesign or
secure-erasure promise. Original Mneme record/key/AAD/signature formats stay unchanged.

## Failed writing

`PlainEntryDraft` holds the form's frozen original record and typed title, text,
labels, date and notebook. Each edit first saves an encrypted recovery capsule,
then attempts the ordinary optimistic entry save. That save atomically removes
ONLY the exact capsule revision. A remote/stale/deleted original fails closed;
the capsule survives. No UI success is displayed before the encrypted commit.

Settings → Recovered conflicts → Resume unsaved writing opens the actual fields.
Retry preserves the original optimistic checkpoint. Save as new entry requires
confirmation and makes a separate text entry; the original/its attachments remain
unchanged and attachments are not duplicated. If two editors compete for one
recovery revision, stale CAS refuses; Keep separate recovery draft retains the
second writer under a fresh local identifier. Capacity256 refuses new capsules,
never evicts them. Latest edits which cannot reach disk are explicitly marked
NOT saved; the app cannot guarantee recovery of bytes a failed disk never stored.

Capsules live ONLY in `VaultSnapshot.conflicts`, using an opaque local kind, and
never enter `records`, push batches or any server API. Their ordinary Codable
record dictionaries are preserved by the old v4 snapshot schema, which cannot
resume them. No version bump or new encryption primitive; existing encrypted
snapshot, Keychain, file protection, backup-exclusion and lock policy applies.
Do not downgrade/uninstall with unsynced work. Physical-device backup/Keychain
acceptance and actual old-binary/device downgrade remain unverified.

## Entry deletion

The existing tombstone and an encrypted original checkpoint now reach the SAME
atomic snapshot commit. A stale/deleted/overflow target refuses before mutation.
Writing/rich drafts, upload queues and ciphertext cache metadata are not removed.
Settings can restore an entry checkpoint as a new entry using the existing full
record restore path. Pending rich drafts keep their original target and still
need explicit reassociation/recovery UX; do not claim that path is fully resolved.

Confirmation explains retained recovery. This is NOT secure erasure. Permanent
recovery pruning, notebook cascade and shared-reference-safe media deletion with
its own durable retry outbox remain incomplete; do not add opportunistic purges.
Retention is a deliberate no-data-loss tradeoff, not a claim of stronger crypto.

## Tests and limits

`PlainEntryDraftTests`: stale CAS/exact finish, old-v4 opaque record preservation,
no publication, capacity refusal, wrong-kind/malformed/overflow, actual encrypted
restart, fault/old-byte preservation, retry and wrong-key refusal.
`EntryLifecycleTests`: offline pending writing/rich/media preservation, restored
opaque content, stale/delete/overflow atomic refusal, encrypted commit failure
and recovery-preserving retry.
New actual native UI test deliberately uses a public fixture WITHOUT identity:
entry publishing must fail; the REAL encrypted local store retains typing and
Settings resumes it. It is not fake authentication, real server CRUD certification
or an actual OS-killed-app recovery test. Check exact revision CI conclusions.
