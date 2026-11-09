# Native whole-block arrangement

Original Mneme crypto, keys, record schema, media IDs and relay format are unchanged.
This is a bounded functional increment, not a finished full rich editor.

- Edit rich entry → Arrange blocks uses native drag handles/Edit and contextual
  Move up/down, with VoiceOver custom actions and real original text previews.
- Each operation moves WHOLE top-level JSON nodes. Root attrs, unsupported future
  nodes, marks, tables, media/gallery/map/interview payloads remain untouched.
- Arbitrary multi-selection uses original insertion-offset semantics, checked
  before index arithmetic. Invalid/empty/out-of-bounds moves fail before mutation;
  actual no-ops do not advance the logical clock or dirty the record.
- A full opening record checkpoint is compared using stable encoded BYTES,
  ignoring only delivery acknowledgement. Same-clock NFC/NFD-only changes refuse
  instead of overwriting. Rich raw-document comparisons likewise use UTF8 bytes.
- The encrypted store commits BEFORE the displayed checkpoint advances. A disk
  error preserves the old snapshot/model; Review latest explicitly reloads a
  changed local record. No silent rebase. Unsynced drafts, uploads, cache and
  recovery originals are not removed or retargeted; old-path drafts fail closed.
- Six new Apple tests cover actual original-web complete-tree fixture and emitted
  original-protocol ciphertext, insertion/bounds/no-op, stale/deleted/duplicate/
  overflow refusal, exact Unicode, draft/media retention and AES snapshot disk
  failure/old bytes/reopen/retry. New native UI test reorders a real block, reopens
  and checks preserved opaque content. Mandatory actual web decoder checks native
  output; no missing native vector is treated as success.

Current verification: actual compiled Foundation source golden tree/preview,
retained draft/stale refusal, adversarial indices and Unicode PASS. At5b2ac8f,
FULL actual Apple suite including all six new tests, mandatory actual Swift→web
ciphertext decoding, original Go verification and genuine universal Simulator
application build/package PASS in42528312711. Actual new Arrange screen gates
must still pass before claiming the screen itself verified. Existing regression and strict normal/
XXXL audits stay required. Older1acd server/live workflow42527124183 is GREEN;
94 page-tour PASS does not certify independently failing production audits.

Remaining: nested/block/table restructuring, arbitrary-position insertion,
selection-based formatting, whole-editor undo, exact math/table/custom rendering
and full two-device visual/usability acceptance. Whole-block movement is not these.

## Permanent media deletion — exact review boundary

The original authenticated `DELETE /v1/media/{id}` is idempotent and owner-scoped
(`server/internal/api/media.go:168–199`), but deletes the index before a best-effort
chunk sweep. Upstream logged some sweep failures and STILL returned204. This increment
corrects that false-success path: original error mapping returns500 on storage
failure or503 when unconfigured, so existing web clients keep their queued
delete intent. Complete/partial-sweep, idempotent retry, unfinalized chunk,
owner/object-prefix isolation and redacted client error tests PASS locally.
The native low-level original API now requires an EMPTY204, rejects other
2xx and unsafe IDs/tokens; native unit and actual TLS/Go/Postgres orphan-object
delete/index+chunk404/retry/unrelated-shared-media tests verify in CI. It cannot
inspect references inside encrypted entries, nor erase provider snapshots/backups.
A client must not label that secure erasure or infer all ciphertext is gone.
Native recoverable deletion deliberately keeps original recovery/drafts/media.
No permanent-purge button or unsafe eager delete was added in this increment.

Next compatible deletion work must explicitly distinguish unlink/recoverable
removal from permanent local+relay deletion, validate retained/live/opaque/draft
references, freeze intent, retain an encrypted durable deletion outbox across
lock/restart/HTTP/disk failure and retry, prevent uploads from resurrecting a
queued deletion, and explain concurrent unseen-client/server-backup limitations.
Test genuine isolated relay/S3 lost-response/sweep-failure and shared references
before exposing it. Do not silently destroy the only copy of unsynced work.

Verified5b actual live relay workflow42528312708 also exercises a separate
UNREFERENCED media object through real normally trusted TLS/URLSession, original
Go/Postgres API: upload, DELETE, metadata+all-chunk404, repeated DELETE, unrelated
shared/recovered original chunk unchanged. Its entire separate real S3/image/
backup-restore workflow passes too; this is NOT a live S3 outage-failure test.
Go full tests/vet and actual partial/complete sweep-failure unit tests pass.
The native low-level strict204/500/503/path/token transport test passes in the
full Apple suite. No native destructive UI or durable purge outbox claimed.

Actual097 native UI context Move down -> changed document order -> reopen ->
opaque future block retained PASSES in42528695109 (87.4s). Genuine after-move PNG:
/workspace/chapter-097-functional-results/ChapterUIAttachments/772AC88B-B24A-441B-AADC-8CB64166D652.png
This is an actual screen interaction + encrypted commit contract, not a physical
kill/relaunch device test. Overall job still fails independent production audits
and card pixel measurement. Full structural/table/custom editing not complete.
