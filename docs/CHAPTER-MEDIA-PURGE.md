# Guarded native media-removal foundation

Status: **core lifecycle implemented; NOT an exposed app feature, NOT complete
media parity**. No new destructive button or automatic remote deletion is enabled.
Original server encryption, keys, authentication, chunk AAD and wire format stay
unchanged. Existing original authenticated DELETE is used only by isolated tests.

## Why stage the implementation

The original server cannot inspect encrypted journal references. No client-only
check can atomically fence another device's unsynced/concurrent reference. A full
pull is necessary but is not a distributed transaction or proof of global absence.
Before exposing removal, the UI/drain must explain that boundary, require genuine
user intent, pull first, and preserve/repair ciphertext if references arrive during
an in-flight request. No claim of secure erasure, SSD overwrite, provider backup
removal, or removal from other devices is made.

## Real implemented contracts

- `MediaPurgeIntent` is retained in the existing encrypted LOCAL opaque recovery
  records, not the synced records array. No local field/schema/key change is
  needed. Older readers preserve its full dictionary, cannot restore it as an
  entry, and do not silently drop an unknown deletion outbox. Tests roundtrip it
  through the older known-fields snapshot representation.
- Review checkpoints compare deterministic exact bytes of the whole snapshot.
  Clock/cursor/content/Unicode/rich-draft/upload/recovery changes require re-review.
- Require a unique matching cached object, bounded original chunk/cipher totals;
  reject same-ID pending uploads, ANY unsynced record or rich draft, live/deleted/
  recovery references, escaped IDs, unknown record fields/nodes/attributes/marks,
  unknown nested gallery schemas, malformed attachments and uninspectable recovery.
  Conservative refusal is preferable to deletion. IDs inside ordinary text may
  intentionally over-protect. This does not assert support for arbitrary future
  opaque encodings or canonically duplicate JSON object keys.
- State machine: `queued` -> `sending` -> `confirmed` -> local cleanup/completion.
  A caller MUST durably save `sending` BEFORE HTTP, and save `confirmed` only after
  strict authenticated204, BEFORE physical cleanup. Sending may retry idempotently
  after interruption; it cannot claim cancellation before a request was seen.
  Only still-queued intent may cancel. Every transition uses exact revision CAS
  and rechecks protections; overflow/malformed/duplicate intents fail closed.
- Physical encrypted-file removal requires the exact confirmed intent and repeats
  all protection checks. Missing files are success after an interrupted final
  acknowledgement. Only the intended object/cache/intent is removed; unrelated
  chunks, cache, uploads, journals and recovery remain unchanged.
- New references after send refuse acknowledgement/cleanup and retain encrypted
  cache + intent. **The production repair/re-upload UX/drain is still missing**;
  this is why no destructive production control is enabled yet.

## Verification

SEVEN actual Foundation/XCTest lifecycle cases pass locally together with SIX
Unicode sync cases (13 tests,0 failures). Nine purge tests total are committed:
seven Foundation tests plus TWO required real Apple encrypted snapshot/file fault,
restart, old-byte preservation, original-key reopen and cleanup retry tests.
The latter two await genuine macOS CI, not substituted Linux crypto.

The genuine TLS/Go/Postgres native integration now additionally stages and saves
an isolated synthetic orphan intent, reloads `sending`, performs original DELETE,
saves confirmed, retries physical cleanup before final acknowledgement, checks
all remote index/chunks404 and preserves unrelated shared media. It remains a
fixture-scoped orphan lifecycle, NOT proof of whole-vault concurrency fencing;
this latest extension must PASS its real macOS live job before being certified.

## Remaining before user-facing completion

1. Actual Apple/fault and real-relay lifecycle tests passing on latest source.
2. Exact typed authenticated completion/caller sequencing, fresh complete pull,
   bounded foreground drain, explicit review/cancel/retry UI and durable locking.
3. In-flight reference arrival/repair, real S3 outage/error integration, crash/kill
   and stale selection UX tests; no deletion of unsynced or shared data.
4. Explicit recoverable unlink versus permanent removal/recovery pruning policy;
   never silently discard old writing to make an object appear unreferenced.
5. Real UI/accessibility/screens and physical-device storage acceptance.
