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
| Notebooks | Browse/create; rename, subtitle, original color and cover metadata editing with optimistic stale-write rejection | Four actual Apple notebook tests, actual Swift→web ciphertext decoding and real native UI Save/persist test PASS at 6c7908c in run 42513126159. Unknown fields/IDs preserved. Cascade delete/media purge missing. Archive/reorder are not present in the reviewed original notebook API; do not invent a wire format or claim those synced. |
| Local discovery | Text/label substring search, day calendar, entry/day counts | Full query, heatmap/stats/streak/badge parity missing |
| Native rich viewing | Styled inline marks, headings, paragraphs, lists/tasks, quotes/code, approximate tables, source math, simplified media/location/interview cards | New web-generated golden document and actual Foundation logic tests. Actual Apple core tests and Simulator compile passed at b8ba3d9; actual rich UI/task/text-run edit passed in run 42511652869; strict onboarding audits still fail; unknown nodes kept opaque |
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
| Appearance/language | Actual encrypted web↔native theme round trip, native restart/offline editing, six skins/palettes and real native theme/cover UI test passed; browser transaction/recovery increment under verification | Updated Chapter web required (original upstream stores themes only locally). Native opaque screen background mismatch was screenshot-proven and fixed, awaiting screenshot pixel verification. Strict onboarding audits still fail; 12 locales/RTL and whole-app/device audits missing |
| Reminders/lifecycle | Background lock only | Reminders, phrase creation/rotation, vault/journal deletion, WebAuthn/PRF and operator administration/update UI missing |
| Sync reliability | Debounced local-edit + foreground sync, bounded retry backoff, up to 10,000 attempted records/pass in 100-record batches, durable media ordering, recoverable entry conflicts | Existing core adversarial ack/clock/conflict tests passed; new drain/backoff/strict-ack + real native TLS/Postgres integration tests pending current CI. No guaranteed background schedule or full two-device lifecycle certification |
| Local storage | Device-only user-presence Keychain + AES-GCM snapshot; protected/excluded from backup | Version 1/2→3 read migration preserves keys and old file until next save; older previews reject v3 instead of dropping rich drafts/media outbox. Actual hardware Keychain/backup extraction not certified |
| Server distribution | Chapter-owned source-build compose/install profile, separate volumes, private setup, optional STT; image/source artifact + real S3/backup-restore CI added | Real source-image builds, trusted HTTPS/auth/web crypto, actual PostgreSQL/S3 media and restore into a different empty stack PASS at 551236b (run 42511822303). Downloadable Linux amd64 image/source/checksum bundle exists. Not deployed; no direct live-volume migration or general historical-upgrade certification |
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
- Currently no ciphertext cache quota/eviction UI, orphan-cipher sweep, guaranteed background
  retry scheduler, or one-button repair for a corrupt regenerable downloaded cache.
  Unsynced data is backup-excluded/device-key-bound: losing the device/key can lose
  unsynced entries/queue; this is NOT a backup/recovery solution.
- Real native media authoring UI, camera/microphone capture, large media and a live
  phone→relay→web→phone test are not certified by Foundation/core transcript tests.
  Chapter-owned Linux amd64 packaging now passed the separate real-stack gate;
  native live relay and phone/device lifecycle certification remain separate.

## Resumed stage — November 8, 2026, 1:37 PM EST onward

No worker ran uninterrupted overnight. Baseline b1c0826 has 34 real macOS core tests,
web reverse decoding, Go signature verification and universal Simulator build passed.
UI failures: required Dynamic Type audits remain open; rich editing smoke reached
its modal, but a globally queried label matched both the sheet and underlying
reader. A stable text-run navigation ID now fixes that ambiguity (not an audit
suppression); actual corrected UI execution remains the gate.

New test-only real TLS relay uses actual PostgreSQL/router/migrations and memory
media, with a disposable CA normally trusted only in ephemeral CI. Native production
URLSession integration test exercises auth, 205 records/paginated pulls, media-reference gating and
ciphertext upload/download, then the actual web decoder checks server-returned
native data. A distinct complete Docker-stack gate tests real S3 + backup restore
into a different empty project and exports Chapter-owned images/exact source only
on success. The Docker/S3/backup-restore gate PASSED at 551236b in run
42511822303, and exported artifact 13629688308 (`Chapter-server-linux-amd64`).
The native TLS/Postgres gate is still running; its result is NOT inferred from
the successful web/S3 test. The updated ordinary native core, actual web/Go
interoperability and universal Simulator build steps passed at 2547d20 in run
42511652869; actual UI/accessibility verification remains in progress.

Fixture migration access is restricted to one exact loopback port/database/query;
adversarial tests reject libpq host/db overrides, credentials and alternate paths.
The native live pagination test now terminates on excess pages instead of merely
asserting and continuing indefinitely. Neither changes production server behavior.

Local Docker is absent. Attempting to obtain isolated PostgreSQL binaries through
APT failed because the configured repository returned HTTP 500 / unsigned InRelease;
no signature check was bypassed and no user database was substituted. Local Go tests,
fixture-host compile/negative opt-in guard and private packaging-script regressions
can run; real database/container/native execution is delegated to the explicitly
configured isolated GitHub runners. See docs/CHAPTER-SERVER.md for installation,
certificate, source/artifact, volume safety, backup and restore details.

## Explicit matching-theme requirement (November 8, 2026, 2:01 PM EST)

Theme matching AND bidirectional web/server/iPhone preference sync is now a required
feature, not optional native tint polish. Source `apps/client/src/hooks/useTheme.ts`
currently persists only `mneme.theme.mode`, `.palette`, `.skin` in localStorage;
there is no existing server theme sync. All six palettes/six skins and three modes
must be covered, including system-mode semantics (each device resolves its own OS).
Keep genuine native controls, matching surface/ink/accent colors and accessibility.
A new encrypted preference schema needs old-client behavior tests: original
`pullEntries` routes unknown record kinds as entries, so blindly adding a new kind
would create phantom entries in older clients. Do not claim compatibility before
that is resolved. No theme/schema change has been implemented in this stage.

The original `updateJournal` supports name/subtitle/color/cover; original
`deleteJournal` also tombstones entries and purges media. This stage implements the
non-destructive original edit operation, not a partial delete pretending parity.
Required audits remain unchanged. An additional minimal unmodified SwiftUI Form
Dynamic Type reproduction is added to distinguish framework behavior from the
production screen; it does NOT replace or suppress the production audits.

## Genuine native network result and hosted-runner teardown diagnosis

In run 42513433243, the actual native URLSession/TLS/Go/PostgreSQL test PASSED
(205 records/pagination, multi-chunk media, repeated-finalization recovery), and
the actual web decoder PASSED on native ciphertext fetched back from that server.
The job nevertheless FAILED: `security remove-trusted-cert -d` hung in cleanup.
The bounded diagnostic exposed the exact command; this was not an auth/crypto
failure or a license to skip TLS. Earlier duplicate runs were canceled only after
preserving their logs and the already-completed server artifacts, freeing CI slots.

Known hosted-macOS issue: https://github.com/actions/runner-images/issues/12116 .
The corrected test harness deletes ONLY its random fixture certificate by exact
platform fingerprint, verifies absence from the System keychain, and refuses to
run outside a disposable GitHub-hosted macOS VM. It does NOT change authorizationdb,
disable TLS checks, trust arbitrary certificates, or touch a persistent/user Mac.
GitHub destroys the VM after the job, including residual trust metadata:
https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners
The corrected ENTIRE workflow PASSED at 1189383 in run 42513915967:
package-and-clean-stack AND native-live-relay, including fingerprint deletion
verification and clean job exit. This is real native core→URLSession→trusted TLS→Go/
PostgreSQL→media→web reverse decoding, not whole SwiftUI/device or native→S3 proof.
The distinct complete Docker gate proves actual S3 + backup/restore.

Separate storage review follow-up: native snapshot save currently performs a
throwing backup-exclusion attribute update AFTER the atomic content write. A
post-write attribute error can make memory disagree with durable disk. Add a tested
pre-commit metadata/write design or explicit uncertain-commit recovery before
release; do not silently retry over newly committed state. Original wire crypto
is unrelated and must remain unchanged. Entry deletion/media purge/outbox cancellation
also needs full lifecycle acceptance; do not label tombstoning alone media parity.

## Verified notebook milestone and controlled accessibility comparison

Run42513126159 at6c7908c executed43 native cases:42 passed and1 intentional live-test
skip (the separate real live gate executes that case). Actual Swift→web notebook
ciphertext decode, Go signatures, universal Simulator build and notebook UI rename/
persist PASS. Real screenshots: artifact13631060358; local reviewed screenshot
`/workspace/chapter-notebook-6c-ui/ChapterUIAttachments/BF47A7C3-61EB-4B07-8090-A52DF0AF3856.png`.
Full native workflow still FAILS both required production Dynamic Type audits.

The completely unmodified SwiftUI Form + string-title Button diagnostic PASSED
strict Dynamic Type in the SAME Simulator/test run. Therefore framework-wide
failure is NOT established. The production action's custom Text/font/fixedSize/
frame/padding wrapper is now replaced with the genuinely plain string-title Button
pattern that passed, keeping the action/auth/validation logic unchanged. Both
original strict audits and real XXXL geometry remain required; this controlled
production change needs actual next CI execution before calling accessibility fixed.

Shared matching themes remain REQUIRED and NOT implemented. Source investigation
also found a possible compatible appearance extension inside the original encrypted
AiSettings settings object: the original codec and form spread preserve unknown
settings fields, unlike unknown top-level record kinds. Evaluate with real old/new
client tests before choosing it; preserve all AI fields/secrets and do not enable
AI or issue external requests just to save appearance. This is a design candidate,
not a schema change or completed sync feature.


## Current appearance/visual increment (verification pending)

- Added updated-web/native shared appearance extension in the existing encrypted settings record; original encryption unchanged. All original skin/accent/mode combinations and mobile book-cover patterns are represented. Local browser check/build and Foundation mutation/catalog checks pass; macOS ciphertext/restart/live TLS and actual screenshot gates must pass before declaring this feature verified.
- Native equal-clock settings conflicts remain recoverable with explicit appearance-only reapply; automatic browser equal-clock convergence and provider durability/race tests remain open. Original upstream web cannot synchronize its local theme UI; updated Chapter web is required. See `CHAPTER-APPEARANCE.md`.
- Whole-app visual parity is NOT achieved by adding themes or covers. Original web notebook preview has been prepared from actual source/public samples for comparison; native typography/surfaces, rich custom nodes, all controls and remaining feature groups still require translation and visual/device acceptance.
- Local backup metadata ordering corrected to avoid a known post-commit throwing operation; Apple fault-injection test pending. Existing encrypted storage/wire formats unchanged.

- Verified narrower appearance milestone: actual original-web encrypted seed → real Go/Postgres/TLS → native URLSession → offline encrypted snapshot reload/edit → native push → actual web decrypt PASS at `a5eccdd` in run42515672358/native-live-relay. Older write rejection, disabled AI and opaque settings preservation passed. This does not establish full rendered appearance, all conflict/provider races, strict accessibility or iPhone installation.
- Whole-app source-to-native visual acceptance matrix: `CHAPTER-VISUAL-PARITY.md`. The actual web preview is available locally for parent visual review; no web visual comparison has been falsely claimed.


## Browser durable theme/settings journal increment — November 8, 2026, 2:58 PM EST

Production settings provider now serializes load/edit/pull/ack, waits for IndexedDB transaction COMMIT, stores owner-scoped encrypted outboxes/tombstones and recovery copies, and rejects stale cross-tab writes atomically. Equal-clock server-authoritative conflicts converge while retaining the displaced configuration encrypted; recovery UI restores theme without changing credentials or restores assistant configuration **disabled**. Lock closes queued work; rotation carries encrypted recovery checkpoints forward without changing original cryptography. See [precise compatibility and tests](CHAPTER-BROWSER-SETTINGS.md).

Local TypeScript compilation, all 28 client regression scripts and production build passed. Production browser journal fault/concurrency/restart tests use standards-based fake IndexedDB, not physical browser power-loss testing. Extended actual trusted TLS relay round trip and new native pixel assertion must pass CI before this increment is called end-to-end verified. Full phrase-rotation lifecycle, recovery-cap management, older cached-client local-outbox downgrade behavior and physical device tests remain release gaps.

Actual a5 native theme picker/cover UI test passed. d4 screenshots diagnose real low-contrast dark text on a brown unlock button; this increment explicitly uses original theme ink/paper for that action and adds native keyboard Next focus navigation. ALL strict audits remain required, including unresolved opaque XXXL Dynamic Type finding. Native row/form/list paper backgrounds now use original tokens directly rather than a hidden root-only background; pixel test asserts actual Forest paper, not a manufactured reference.
