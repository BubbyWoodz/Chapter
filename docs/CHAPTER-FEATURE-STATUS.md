# Chapter native feature and verification status

The original Mneme encryption, keys, AAD/signature domains and relay formats are
unchanged. This is an unfinished native preview, not full parity or an installable
iPhone release. “Implemented” is not “live server/device verified”. Check PR CI for
the exact revision; a failing strict accessibility audit remains a release blocker.

| Feature group | Actual native scope | Tests/evidence and remaining gap |
|---|---|---|
| Existing-vault recovery/authentication | English BIP39 validation, real owner-authorized registration/challenge/session; direct HTTPS URL | Native key/auth HTTP transcript and actual web/Go signature checks passed before this slice; real approval/recovery/phone integration still needed |
| Connectivity/privacy | LAN/Tailscale URL/path; trusted TLS; no redirects/telemetry/cloud requirement | URL/HTTP rejection tests; physical permission, certificates and LAN/VPN matrix not run. HTTP LAN unsupported |
| Entries | Plain CRUD/date/labels/notebook; encrypted failed-writing recovery, close/resume/retry/separate recovery/save-as-new; atomic deletion recovery checkpoint | Actual Apple encrypted fault/restart/old-byte preservation and actual failed-writing→Settings→resumed-editor UI PASS at4d9e6d3 (42520947366). Original encryption unchanged; this is not physical-device certification. Delete retains drafts/uploads and explicit encrypted original; not secure erasure or media purge. Broad two-device controller CRUD not certified |
| Notebooks | Browse/create; rename, subtitle, original color and cover metadata editing; real non-destructive move-between-notebooks with optimistic stale-write rejection | Four actual Apple notebook tests, actual Swift→web ciphertext decoding and real native UI Save/persist test PASS at 6c7908c in run 42513126159. Unknown fields/IDs preserved. Move whole-document preservation, stale/deleted/overflow and actual Swift→web reverse decoding PASS at fd3d1ad (42519352453); real new Move UI gate is still pending. Cascade delete/media purge missing. Archive/reorder are not present in the reviewed original notebook API; do not invent a wire format or claim those synced. |
| Local discovery | Text/label substring search, day calendar, entry/day counts | Full query, heatmap/stats/streak/badge parity missing |
| Native rich viewing | Styled inline marks, headings, paragraphs, lists/tasks, quotes/code, approximate tables, source math, simplified media/location/interview cards | New web-generated golden document and actual Foundation logic tests. Actual Apple core tests and Simulator compile passed at b8ba3d9; actual rich UI/task/text-run edit passed in run 42511652869; strict onboarding audits still fail; unknown nodes kept opaque |
| Rich editing | Existing text-run/task editing, five whole-run format toggles, nine-style new block authoring and re-editable empty known blocks; patch original JSON | New tests assert full tree/unknown attrs/marks/media IDs retained, stale writes rejected, Unicode/empty-run behavior. Actual Apple authoring/encrypted draft migration and original schema/reverse-codec PASS at98885d0 (42518974244); universal Simulator app builds. New real authoring UI and all strict audits remain required/pending. New explicit-save rich title/date/individual-label controls preserve exact rich JSON and unknown label schemas; new core/reverse-web/UI gates pending. No full selection-based editor, arbitrary-position existing-block restructuring or full custom-node editor |
| Rich local drafts | Encrypted autosaved text/formatting/new-block drafts; resume in Settings; explicit apply rejects changed/deleted/wrong-ID records | New native migration/encrypted recovery tests and real Debug fixture UI edit test added; device failure/restart/disk-full acceptance not complete |
| Rich cross-client sync | Same encrypted record protocol after patch, regenerate bodyText with actual web docToText semantics | Native-produced edited ciphertext must open in actual web decoder with entire expected tree/media IDs. Passed at b8ba3d9 in macOS CI; not a live server/browser round trip |
| Entry links/Markdown/math | Stored link labels and LaTeX source retained; external web/mail links require explicit confirmation | Backlink/navigation UI, Markdown/source editing and exact native math typesetting missing; no silent external fetches |
| Media download | Explicit authenticated chunk download, encrypted durable ciphertext cache, offline cached/pending previews, Quick Look, protected temporary plaintext | Native/web media crypto checks; 128 MiB cap, OS codec limits; real-stack/device playback and cleanup not certified |
| Media authoring/offline | Files + selected Photos image import; original 1 MiB chunk crypto; durable encrypted upload queue; retry/lost-finalize-ack recovery; upload-before-reference ordering | 34 native tests, actual web chunk/attachment-record decoding and Simulator build passed at b1c0826. 128 MiB cap. Camera/audio/video capture, large-file/codec parity and actual device/provider interruption acceptance still missing |
| Templates/interview types | Opaque sync/preservation only | Native management/application UI missing |
| AI/Q&A/guided/freeform interviews | NOT implemented | Native configuration, explicit destination consent and operator-policy behavior missing |
| Audio/transcription/video/films | Read-only simplified cards/transcripts + existing attachment preview | Recording, per-question capture, STT, film rendering/editor all missing |
| Locations/maps | Read-only place names and explicit encrypted attachment previews | Native insertion/editing/snapshot flows and explicit network consent missing |
| Import/export/backups | NOT implemented natively | Day One, journal exports/import, recovery/restore and operator backup UI missing |
| Appearance/language | Actual encrypted web↔native theme round trip, native restart/offline editing, six skins/palettes and real native theme/cover UI test passed; browser transaction/recovery increment under verification | Updated Chapter web required (original upstream stores themes only locally). Native Forest paper screenshot RGB assertion and actual cover/theme picker PASS at929e8ea run42517557894. Strict onboarding audits still fail. Original Hanken Grotesk/Newsreader/Spline Sans Mono/skin typography is not yet faithfully applied natively; 12 locales/RTL and whole-app/device audits missing |
| Reminders/lifecycle | Background lock only | Reminders, phrase creation/rotation, vault/journal deletion, WebAuthn/PRF and operator administration/update UI missing |
| Sync reliability | Debounced local-edit + foreground sync, bounded retry backoff, up to 10,000 attempted records/pass in 100-record batches, durable media ordering, recoverable entry conflicts | Actual core adversarial ack/clock/conflict/drain/retry and genuine trusted TLS/Go/Postgres native relay/pagination/media/theme round trips PASS; latest whole native/S3/backup-restore42519352385 PASS atfd3d1ad. No guaranteed background schedule or full two-device lifecycle certification |
| Local storage | Device-only user-presence Keychain + AES-GCM snapshot; protected/excluded from backup | Version 1/2/3→4 read migration preserves keys and old file until next save; older previews reject v4 instead of dropping formatting/new-block drafts/media outbox. Actual Apple v3→v4 encrypted migration/restart/old-version write refusal PASS at98885d0; earlier backup-preparation fault/reopen/retry PASS. Actual hardware Keychain/backup extraction not certified |
| Server distribution | Chapter-owned source-build compose/install profile, separate volumes, private setup, optional STT; image/source artifact + real S3/backup-restore CI added | Real source-image builds, trusted HTTPS/auth/web crypto, actual PostgreSQL/S3 media and restore into a different empty stack PASS at 551236b (run 42511822303). Downloadable Linux amd64 image/source/checksum bundle exists. Not deployed; no direct live-volume migration or general historical-upgrade certification |
| iPhone distribution | Xcode source and unsigned Simulator artifacts only | No signed device IPA, TestFlight or physical-device certification. Apple signing route later, not obtained here |

## November 8, 2026, 3:57 PM EST increment (new metadata Apple gates pending)

- Real failed-writing → close → Settings encrypted recovery → resume native editor
  screen test PASSED in42520947366, with an actual screenshot artifact. Apple
  encrypted fault/restart/old-byte tests, original-web reverse crypto, original Go
  verifier and universal Simulator build also passed. That run is NOT green: both
  strict production Dynamic Type audits and two real Menu interactions still fail.
- Rich entries now have a real explicit-save title/date/individual-label form.
  Commas stay inside one label; existing imported spelling and unknown future
  label schemas are preserved. Changes patch ONLY requested fields, never parse
  or rebuild rich JSON/media. Optimistic body/clock guards reject concurrent edits;
  ack-only/no-op saves do not bump clocks. Unsaved metadata is NOT autosaved:
  Cancel confirms discard and dirty swipe dismissal is blocked; save before lock.
- New actual-source Linux Foundation regressions PASS for lossless metadata,
  stale/overflow/invalid dates/opaque labels/no-op and web Unicode golden cases.
  A real Greek final-sigma mismatch was caught and fixed using Foundation root-
  locale whole-string casing, not a custom case algorithm. New Apple tests and
  native-encrypted ciphertext → actual original-web decoder checks are required,
  not declared passing from Linux syntax/harness results.
- Moving Menu wrappers into content did NOT resolve actual AX scroll-to-visible
  failures. Replaced them with actual native Buttons and expandable action rows;
  formatting selection still runs the same durable-draft operations. Plain Edit
  now also uses real action buttons. All strict tests/assertions remain. New UI
  verification is pending; Dynamic Type release blocker remains independently.
- Notebook cascade/shared-media purge and licensed original font integration are
  still outstanding. Deletion recovery is intentionally NOT secure erasure.

## November 8, 2026, 3:36 PM EST increment (verification pending)

- Failed plain autosave now first commits a LOCAL-ONLY opaque recovery record in
  the existing encrypted conflict collection, then atomically saves the entry and
  removes exactly that recovery revision. A stale original is not overwritten;
  typed title/text/date/labels/notebook can be resumed in Settings or explicitly
  saved as a new text entry. Attachments are not duplicated by that explicit copy.
  A separate recovery option preserves two competing draft editors; revision CAS
  and a256-draft fail-closed cap never evict work. No new server record kind/key/
  encryption/snapshot version; old v4 opaque dictionaries retain it but cannot
  resume it. Existing v3 downgrade restrictions still apply.
- Delete entry now commits an encrypted original recovery checkpoint TOGETHER
  with its existing tombstone; queued uploads, rich drafts and writing recoveries
  remain intact. Confirmation explicitly discloses retained recovery/not secure
  erasure. Notebook cascade/permanent media purge remain NOT implemented.
- Actual compiled Foundation code tests pass for CAS, exact restart/finish,
  capacity refusal/no eviction, preserved original records and stale/offline
  deletion safety. New Apple encrypted fault/restart/old-byte preservation and
  actual native failure/resume UI tests are added, not yet declared passing.
- Completed988 UI42518974244: existing rich/task editing, covers/palette pixels,
  notebook Save, keyboard/HTTP and BOTH normal + actual-XXXL unmodified native
  Form comparisons PASS. New formatting flow FAILS real toolbar AX scroll/tap;
  strict production audits still FAIL. Normal audit now precisely names the
  system Form header `UNLOCK VAULT` as partially non-scaling. Formatting menu
  moved to a44pt content control and section headings to genuinely scalable
  body rows with header traits; all tests/audits retained, fixes verifying.
- Completedfd3 UI42519352453 separately confirms Move fails the same unreachable
  implicit toolbar Menu AX action (`More`), not the move core or server. More now
  uses an actual44pt native content menu like formatting; tests/assertions remain
  unchanged and the new placement is not yet certified. That run also precisely
  identifies the SERVER system header; both production headers were corrected.
-332 Apple core42519961437 fails ONE fixture assertion: test bodyJson text did
  not match omitted bodyText, so correctly was not a canonical plain entry. The
  fixture now supplies matching bodyText; assertion is unchanged. Do not claim
  the332 entire native gate passed. Original protocols/keys/journals untouched.

## November 8, 2026, 3:24 PM EST checkpoint

Authoring98885d0 actual Apple core/encrypted migration, Swift→original-web reverse
ciphertext, original Go verifier and universal Simulator build steps PASS in
42518974244; its real authoring UI and strict audits are still running. The subsequent
lossless-move fd3d1ad core/actual-web steps PASS in42519352453; its app/UI steps are
still verifying. Full ordinary CI and genuine native/S3/backup-restore42519352385
PASS atfd3d1ad. This is not full parity or a device release.

A final controller review found that plain-editor autosave was looking up a fresh
record before its stale guard, implicitly rebasing old form text over a newer plain
entry. The form now freezes its loaded/last-successfully-committed record and only
advances that checkpoint after the encrypted commit returns the actual record.
Equal/newer-clock remote body changes fail closed; acknowledgement-only dirty flag
changes remain allowed. Actual Foundation contract tests pass; an additional Apple
regression case is required in the next head. Source syntax parsing is not Apple
compilation or a two-device UI-race acceptance test.

Genuine upstream-provided `docs/screenshots/mobile-journal.png` and
`desktop-editor.png` have been inspected as references (cream paper, patterned cover,
teal-edged entry cards, serif prose/headings). They are NOT a live notebook-shelf
render. Parent browser could not load either local synthetic preview route; do not
claim whole-app visual parity or request another retry without diagnosing routing.

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


## Native authoring increment — November 8, 2026, 3:14 PM EST

Implemented real SwiftUI run formatting (bold/italic/underline/strike/inline code), resumable encrypted formatting drafts and native nine-style block authoring: paragraph, three headings, quote, bulleted/numbered/task list and code block. Empty known text blocks can be edited again after deleting their last run. The editor now derives its rows from the live saved document instead of retaining a stale opening tree. Native-created plain entries retain their existing text/details editor and additionally offer the rich editor. This is NOT a selection-based full editor: inserting at arbitrary positions, moving/deleting/restructuring existing blocks, merged tables/math/custom-node editing and undo/redo remain open.

Original rich JSON/opaque nodes/attrs/marks/media references are preserved. Inline code follows original schema exclusion; opaque mark/link removal is refused rather than silently discarded. Actual upstream ProseMirror schema checks newly authored blocks and supported mark combinations; frozen complete tree/preview/media expectations feed Apple-produced ciphertext reverse decoding. Actual Foundation subset execution and local web regressions/build passed; Apple full core/encrypted migration/reverse ciphertext and new real UI authoring test are required CI gates, not yet claimed passing.

Native LOCAL snapshot v4 adds optional formatting/new-block draft metadata. Reads v1–v3 with existing AES-GCM key/format, without rewriting on load; next save writes v4. Old v3 preview's exact version guard rejects v4 instead of dropping pending formatting. Attempting to save new draft metadata under an older version fails before touching ciphertext. No original server/browser wire/key/cipher change. Do not downgrade/uninstall with unsynced native data. Actual old binary/device downgrade, key custody and interruption tests remain release gates.

Verified earlier929 UI now PASSES the real Forest notebook screenshot RGB assertion, cover selection, native keyboard Next + HTTP rejection, rich/task edits and notebook Save. Actual Forest paper screenshot: /workspace/chapter-929-ui-results/ChapterUIAttachments/7285F6FA-2E4C-4B63-8B83-9E83077E0C0A.png . Strict NORMAL audit still fails unknown Text clipped (the shown long last preview row is partially visible); XXXL Dynamic Type remains unknown. Moved the important incomplete-preview disclosure visibly into the intro instead of a long partially visible last row; no strict audit removed. Added a required unmodified native Form test at ACTUAL XXXL (previous minimal comparison only ran normal size). Both are pending genuine CI. No framework-wide false-positive claim.

Parent browser also failed the alternate synthetic preview URL before rendering. NO actual original-web visual comparison was obtained; no further retry requested without a genuinely diagnosed new route. Preview processes stay running; no browser automation through Shell. Full visual parity is NOT certified.


## Native notebook organization increment — November 8, 2026, 3:17 PM EST

Added a real Move entry sheet with native notebook picker, explicit Move/Cancel and optimistic opening-snapshot validation. Rich JSON, IDs, creation date, labels, media references and all opaque metadata remain unchanged; only notebook relation/update clock changes. Commit is encrypted and durable before dismiss; offline sync uses the original outbox. A pending rich draft applies onto the latest record without undoing the move. Stale entry edits, deleted/wrong target and overflow fail closed; no-op/ack-only changes do not invent revisions. Plain edit and entry delete now check the current record before overwriting, protecting against an older plain sheet flattening newer rich content. Apple/web ciphertext and real native move UI tests are required, not yet claimed passing. Foundation actual-source move/doc/draft preservation checks and local web regressions pass. Notebook cascade delete/media purge remains NOT implemented; shared-reference cleanup and durable delete retry must be designed/tested before claiming lifecycle parity.
