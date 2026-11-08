# Chapter native feature and verification status

The original Mneme encryption, keys, AAD/signature domains and relay formats are
unchanged. This is an unfinished native preview, not full parity or an installable
iPhone release. “Implemented” is not “live server/device verified”. Check PR CI for
the exact revision; a failing strict accessibility audit remains a release blocker.

| Feature group | Actual native scope | Tests/evidence and remaining gap |
|---|---|---|
| Existing-vault recovery/authentication | English BIP39 validation, real owner-authorized registration/challenge/session; direct HTTPS URL | Native key/auth HTTP transcript and actual web/Go signature checks passed before this slice; real approval/recovery/phone integration still needed |
| Connectivity/privacy | LAN/Tailscale URL/path; trusted TLS; no redirects/telemetry/cloud requirement | URL/HTTP rejection tests; physical permission, certificates and LAN/VPN matrix not run. HTTP LAN unsupported |
| Entries | Plain entry CRUD, dates/labels, notebook association | Existing core safeguards; broad app/controller/live-stack CRUD not certified |
| Notebooks | Browse/create | Rename/reorder/delete/archive and remaining controls missing |
| Local discovery | Text/label substring search, day calendar, entry/day counts | Full query, heatmap/stats/streak/badge parity missing |
| Native rich viewing | Styled inline marks, headings, paragraphs, lists/tasks, quotes/code, approximate tables, source math, simplified media/location/interview cards | New web-generated golden document and actual Foundation logic tests. Actual Apple core tests and Simulator compile passed at b8ba3d9; corrected real rich UI test still being checked; unknown nodes kept opaque |
| Rich editing | Existing text-run editing and task checked state only; patch original JSON | New tests assert full tree/unknown attrs/marks/media IDs retained, stale writes rejected, Unicode/empty-run behavior. No full selection-based rich editor, structural/formatting toolbar, title/date/label controls for rich records or full custom-node editor |
| Rich local drafts | Encrypted autosaved run drafts; resume in Settings; explicit apply rejects changed/deleted record | New native migration/encrypted recovery tests and real Debug fixture UI edit test added; device failure/restart/disk-full acceptance not complete |
| Rich cross-client sync | Same encrypted record protocol after patch, regenerate bodyText with actual web docToText semantics | Native-produced edited ciphertext must open in actual web decoder with entire expected tree/media IDs. Passed at b8ba3d9 in macOS CI; not a live server/browser round trip |
| Entry links/Markdown/math | Stored link labels and LaTeX source retained; external web/mail links require explicit confirmation | Backlink/navigation UI, Markdown/source editing and exact native math typesetting missing; no silent external fetches |
| Media download | Explicit authenticated chunk download, encrypted durable ciphertext cache, offline cached/pending previews, Quick Look, protected temporary plaintext | Native/web media crypto checks; 128 MiB cap, OS codec limits; real-stack/device playback and cleanup not certified |
| Media authoring/offline | Files + selected Photos image import; original 1 MiB chunk crypto; durable encrypted upload queue; retry/lost-finalize-ack recovery; upload-before-reference ordering | 34 native tests, actual web chunk/attachment-record decoding and Simulator build passed at b1c0826. 128 MiB cap. Camera/audio/video capture, large-file/codec parity and actual device/provider interruption acceptance still missing |
| Templates/interview types | Opaque sync/preservation only | Native management/application UI missing |
| AI/Q&A/guided/freeform interviews | NOT implemented | Native configuration, explicit destination consent and operator-policy behavior missing |
| Audio/transcription/video/films | Read-only simplified cards/transcripts + existing attachment preview | Recording, per-question capture, STT, film rendering/editor all missing |
| Locations/maps | Read-only place names and explicit encrypted attachment previews | Native insertion/editing/snapshot flows and explicit network consent missing |
| Import/export/backups | NOT implemented natively | Day One, journal exports/import, recovery/restore and operator backup UI missing |
| Appearance/language | System-native layout and Dynamic Type | Strict onboarding audits currently fail; exact theme/12 locales/RTL parity, whole-app VoiceOver/device audits missing |
| Reminders/lifecycle | Background lock only | Reminders, phrase creation/rotation, vault/journal deletion, WebAuthn/PRF and operator administration/update UI missing |
| Sync reliability | Debounced local-edit + foreground sync, bounded retry backoff, up to 10,000 attempted records/pass in 100-record batches, durable media ordering, recoverable entry conflicts | Existing core adversarial ack/clock/conflict tests passed; new drain/backoff/strict-ack + real native TLS/Postgres integration tests pending current CI. No guaranteed background schedule or full two-device lifecycle certification |
| Local storage | Device-only user-presence Keychain + AES-GCM snapshot; protected/excluded from backup | Version 1/2→3 read migration preserves keys and old file until next save; older previews reject v3 instead of dropping rich drafts/media outbox. Actual hardware Keychain/backup extraction not certified |
| Server distribution | Chapter-owned source-build compose/install profile, separate volumes, private setup, optional STT; image/source artifact + real S3/backup-restore CI added | Actual new packaging job pending. Not deployed; amd64 artifact only after job passes; no direct live-volume migration or general historical-upgrade certification |
| iPhone distribution | Xcode source and unsigned Simulator artifacts only | No signed device IPA, TestFlight or physical-device certification. Apple signing route later, not obtained here |

## New test files

- `apps/ios/ChapterCore/Tests/ChapterCoreTests/RichDocumentTests.swift`:
  eight native tests for web-preview parity, tree preservation, task/text patching,
  opaque nodes, deletion, stale/malformed inputs, Unicode/overflow, independent
  encrypted web output, and old-local-snapshot/draft recovery.
- `apps/client/scripts/native-rich-vectors.ts`: actual web preview/media-ID fixture
  generator and decoder verification of Apple-produced rich edits. Included in
  the existing native vector check, not an alternative mock crypto implementation.
- `ChapterUITests.testNativeRichRenderingEditingAndTaskPersistence`: actual app
  rendering, real encrypted fixture-store task update, autosaved draft and text
  application. Debug public fixture bypasses production auth by design, so this
  does **not** certify production Keychain or server integration.

No audit category, issue filter or original regression test is removed to get a
passing status. New independent features may progress while accessibility remains
an explicitly unresolved release gate.

## Media stage: invariants and remaining acceptance

- No server, key derivation, cipher, record or media envelope changes. Ciphertext
  bytes total is plaintext bytes + 41 per chunk, including one empty chunk for an
  empty file. The exact original `media:<id>:<i>/<n>` AAD remains in use.
- Every staged chunk is atomically written before a single encrypted snapshot
  commits entry reference + outbox. Entry pushes referencing pending media are
  excluded. Only a complete response (or exact finalized remote-byte comparison
  after a lost acknowledgment) removes the durable outbox.
- Retry reuses immutable ciphertext/nonces/ID; a local corrupt/missing chunk fails
  closed. Namespace/ID/path validation is exact ASCII, not a newline-tolerant regex.
- Protected transient photo copies and Quick Look files are excluded from backup;
  preview files are deleted on dismissal/lock/startup. Lock cancels import and
  relay work; queued ciphertext is deliberately retained. Device lock/background,
  Photos-provider interruption and Quick Look OS-private copies need real-device
  verification. Plaintext cannot be promised zeroized by Swift or the OS.
- Stale rich drafts are retained and rejected after attachment insertion. No old
  client may downgrade/rewrite v3: sync first before returning to an older preview.
  No key regeneration or journal-format conversion occurs on migration.
- Currently no ciphertext cache quota/eviction UI, orphan-cipher sweep, automatic
  retry scheduler, or one-button repair for a corrupt regenerable downloaded cache.
  Unsynced data is backup-excluded/device-key-bound: losing the device/key can lose
  unsynced entries/queue; this is NOT a backup/recovery solution.
- Real native media authoring UI, camera/microphone capture, large media and a live
  phone→relay→web→phone test are not certified by Foundation/core transcript tests.
  Chapter-owned server packaging remains outstanding, not forgotten.

## Resumed stage — November 8, 2026, 1:37 PM EST onward

No worker ran uninterrupted overnight. Baseline b1c0826 has 34 real macOS core tests,
web reverse decoding, Go signature verification and universal Simulator build passed.
UI failures: required Dynamic Type audits remain open; rich editing smoke reached
its modal, but a globally queried label matched both the sheet and underlying
reader. A stable text-run navigation ID now fixes that ambiguity (not an audit
suppression); actual corrected UI execution remains the gate.

New test-only real TLS relay uses actual PostgreSQL/router/migrations and memory
media, with a disposable CA normally trusted only in ephemeral CI. Native production
URLSession proves auth, 205 records/paginated pulls, media-reference gating and
ciphertext upload/download, then the actual web decoder checks server-returned
native data. A distinct complete Docker-stack gate tests real S3 + backup restore
into a different empty project and exports Chapter-owned images/exact source only
on success. These gates are newly added, not claimed passed until CI executes.

Local Docker is absent. Attempting to obtain isolated PostgreSQL binaries through
APT failed because the configured repository returned HTTP 500 / unsigned InRelease;
no signature check was bypassed and no user database was substituted. Local Go tests,
fixture-host compile/negative opt-in guard and private packaging-script regressions
can run; real database/container/native execution is delegated to the explicitly
configured isolated GitHub runners. See docs/CHAPTER-SERVER.md for installation,
certificate, source/artifact, volume safety, backup and restore details.
