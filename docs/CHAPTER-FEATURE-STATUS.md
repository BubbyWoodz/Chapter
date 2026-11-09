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
| Notebooks | Browse; create with the web New journal sheet (name, JCOLORS swatches, cover, Start from a template); rename, subtitle, colour swatches and cover editing like the web Edit journal sheet; real non-destructive move-between-notebooks with optimistic stale-write rejection | Four actual Apple notebook tests, actual Swift→web ciphertext decoding and real native UI Save/persist test PASS at 6c7908c in run 42513126159. Unknown fields/IDs preserved. Move whole-document preservation, stale/deleted/overflow and actual Swift→web reverse decoding PASS at fd3d1ad (42519352453); real Move UI PASS atc810740 in42521928122. Updated native-Button controls verify separately. Recoverable downloaded-set notebook cascade + guarded original-ID restore now implemented; EIGHT new Apple core/fault/Unicode/capacity tests, real native TLS/Go/Postgres cascade/restore/shared-media and actual original-web decrypt/router PASS at be6189b (42525592332/42525592525); new native screen flow verifies separately. New journal sheet UI test with strict audit added in abe0ddd, Apple pending. Permanent/shared-media purge missing. Archive/reorder are not present in the reviewed original notebook API; do not invent a wire format or claim those synced. |
| Local discovery | Search like the web Search sheet (a port of search/core: title, label, date and content matching with the web ranking, date spellings in English and the active language, snippets and field tags); badges like the web (the eight state/badges.ts rules, the Settings gallery, one-at-a-time celebrations and the quiet first-run catch-up); day calendar with the web empty-day text, On this day and the 17-week writing heatmap; Preferences "Your writing" six stats (entries, words, this month, streak, longest, days) from a port of the web state/stats.ts | Stats, heatmap counts and on-this-day match web-generated vectors locally (a996a1c, 19854af); Search (7fbe254: 456 web-generated queries in 12 languages) and badges (964cd01: 22 vaults, 21 catch-up cases) match the web locally; Apple UI tests pending. Badges are evaluated only after the first complete pull, which is stricter than the web when offline |
| Native rich viewing | Styled inline marks, headings, paragraphs, lists/tasks, quotes/code, approximate tables, source math, simplified media/location/interview cards | New web-generated golden document and actual Foundation logic tests. Actual Apple core tests and Simulator compile passed at b8ba3d9; actual rich UI/task/text-run edit passed in run 42511652869; strict onboarding audits still fail; unknown nodes kept opaque |
| Rich editing | Existing text-run/task editing, five whole-run format toggles, nine-style new block authoring and re-editable empty known blocks; patch original JSON | New tests assert full tree/unknown attrs/marks/media IDs retained, stale writes rejected, Unicode/empty-run behavior. Actual Apple authoring/encrypted draft migration and original schema/reverse-codec PASS at98885d0 (42518974244); universal Simulator app builds. New real authoring UI and all strict audits remain required/pending. New explicit-save rich title/date/individual-label controls preserve exact rich JSON and unknown label schemas; actual Apple core, new Swift ciphertext→original-web decoder, original Go verifier and universal Simulator app build PASS ata0f2b1d in42522662183; real new metadata UI and subsequent Unicode/fault-injection improvements verify separately. Native whole-block Arrange screen/drag/context/VoiceOver operations now implemented with byte-exact checkpoints and retained drafts; actual Apple six new tests, original Swift→web decoding and universal Simulator build PASS at5b2ac8f in42528312711; actual Arrange screen gates pending (see CHAPTER-RICH-STRUCTURE.md). Selection formatting inside a run and across a paragraph’s or heading’s runs, at-cursor link/template insertion and unmerged-table editing are verified against the real TipTap/prosemirror-tables (see the dated sections below). No typing across runs, nested restructuring or full custom-node editor |
| Rich local drafts | Encrypted autosaved text/formatting/new-block drafts; resume in Settings; explicit apply rejects changed/deleted/wrong-ID records | New native migration/encrypted recovery tests and real Debug fixture UI edit test added; device failure/restart/disk-full acceptance not complete |
| Rich cross-client sync | Same encrypted record protocol after patch, regenerate bodyText with actual web docToText semantics | Native-produced edited ciphertext must open in actual web decoder with entire expected tree/media IDs. Passed at b8ba3d9 in macOS CI; not a live server/browser round trip |
| Entry links/Markdown/math | Stored link labels retained; external web/mail links require explicit confirmation; inline and display math typeset with the web's own KaTeX 0.18.4 and options, offline in a script-free view | Apple run 42614136563: native KaTeX output equals the web byte-for-byte, and the on-screen typesetting UI test passes. Backlink UI and Markdown/source editing missing; no silent external fetches |
| Media download | Explicit authenticated chunk download, encrypted durable ciphertext cache, offline cached/pending previews, Quick Look, protected temporary plaintext | Native/web media crypto checks; 128 MiB cap, OS codec limits; real-stack/device playback and cleanup not certified |
| Media authoring/offline | Files + selected Photos image import; original 1 MiB chunk crypto; durable encrypted upload queue; retry/lost-finalize-ack recovery; upload-before-reference ordering | 34 native tests, actual web chunk/attachment-record decoding and Simulator build passed at b1c0826. 128 MiB cap. Camera/audio/video capture, large-file/codec parity and actual device/provider interruption acceptance still missing |
| Templates/interview types | Native template manager (create/rename/delete/edit body), the original built-ins in all 12 web languages, start an entry from a template and insert one at the cursor; synced template bodies are edited with the same rich editor as entries (no entry links, media or nested templates, like the web); interview types are preserved opaquely | Template body edits pass the web schema and docToText locally (eaeb9d1). Built-in bodies are editable too: like the web mutateSeeded, the first applied change forks the seed into a synced record with its builtin slug, and an unsaved edit forks nothing (a9c2fd5). Apple UI tests pending. Interview types are managed like the web InterviewTypesSheet (b1001b1): the 15 built-ins fork on the first real change, an unchanged save forks nothing, and deleting a built-in writes a `deleted: true` fork; the create/fork/tombstone wire bodies equal the web `toPushInterviewType` |
| AI/Q&A/guided/freeform interviews | NOT implemented | Native configuration, explicit destination consent and operator-policy behavior missing |
| Audio/transcription/video/films | Read-only simplified cards/transcripts + existing attachment preview | Recording, per-question capture, STT, film rendering/editor all missing |
| Locations/maps | Location cards rendered like the web LocationCard: the map and travel photo are decrypted from the user's own encrypted media (local queue or cache first, then the user's relay), with "from → to" labels and the web's distance formatting | Coercion, haversine and distance in 12 languages pass on Apple (42614136563). The decrypt/German UI test reached its strict audit, which flagged a short selectable paragraph; fixed in 7f6b820, awaiting Apple. Creating or editing cards (needs explicit consent for third-party map tiles) is missing; malformed cards show a marker where the web shows nothing |
| Import/export/backups | Export a journal from Settings (33f506b), like the web ExportJournalSheet | The archive is the same `mneme-journal-export` v1 zip as the web `exportJournal`: every file matches, markdown included, and the web's fflate reads the native zip back identically. It is streamed one file at a time and includes the progress steps. Media comes from the upload queue, the local cache or the relay; anything else is recorded as missing. The plaintext archive goes to the share sheet and is deleted when the sheet closes, when the vault locks and on the next launch. Locking mid-export aborts it. Apple UI test pending. Day One import groundwork is native and verified against the web code: the markdown-to-blocks conversion, title split and moment URLs (4086c7c), plus a ZIP reader that returns the same members, in the same order and with the same bytes as fflate `unzipSync` (ed36fed, 637307c). The archive parse (26b9888) and the import run (51dfeab) are native too. The run sits in ChapterCore behind a small app interface, and its calls match the web `importDayOne` on a recording mock. Missing: the app adapter and import sheet, markdown import, and recovery/restore and backup UI |
| Appearance/language | Accent shades (accent-ink, accent-soft, accent-line) derived from the palette exactly like the web useTheme, checked per palette against the web (19854af); actual encrypted web↔native theme round trip, native restart/offline editing, six skins/palettes and real native theme/cover UI test passed; browser transaction/recovery increment under verification | Updated Chapter web required (original upstream stores themes only locally). Native Forest paper screenshot RGB assertion and actual cover/theme picker PASS at929e8ea run42517557894. Strict onboarding audits still fail. Original licensed Hanken Grotesk/Newsreader/Spline Sans Mono normal/italic Latin faces are now bundled and applied to journal/notebook headings, prose/editor/code and unlocked UI default using original skin roles. Font tables/glyphs, byte-reproducibility/provenance/license checks and native role-selection tests PASS locally; Actual six-face UIFont loading, font-screen strict Dynamic Type audit and offline license viewer PASS at ae4f0be6 in42523109089 and a7c9fdba in42523742373; production onboarding strict audits still FAIL. Onboarding/native navigation and unavailable glyphs retain native fallback. Live web visual comparison,12 locales/RTL and whole-app/device audits missing |
| Reminders/lifecycle | Background lock only | Reminders, phrase creation/rotation, permanent vault deletion, WebAuthn/PRF and operator administration/update UI missing |
| Sync reliability | Debounced local-edit + foreground sync, bounded retry backoff, up to 10,000 attempted records/pass in 100-record batches, durable media ordering, recoverable entry conflicts | Actual core adversarial ack/clock/conflict/drain/retry and genuine trusted TLS/Go/Postgres native relay/pagination/media/theme round trips PASS; latest whole native/S3/backup-restore42519352385 PASS atfd3d1ad. No guaranteed background schedule or full two-device lifecycle certification |
| Local storage | Device-only user-presence Keychain + AES-GCM snapshot; protected/excluded from backup | Version 1/2/3→4 read migration preserves keys and old file until next save; older previews reject v4 instead of dropping formatting/new-block drafts/media outbox. Actual Apple v3→v4 encrypted migration/restart/old-version write refusal PASS at98885d0; earlier backup-preparation fault/reopen/retry PASS. Actual hardware Keychain/backup extraction not certified |
| Server distribution | Chapter-owned source-build compose/install profile, separate volumes, private setup, optional STT; image/source artifact + real S3/backup-restore CI added | Real source-image builds, trusted HTTPS/auth/web crypto, actual PostgreSQL/S3 media and restore into a different empty stack PASS at 551236b (run 42511822303). Downloadable Linux amd64 image/source/checksum bundle exists. Not deployed; no direct live-volume migration or general historical-upgrade certification |
| iPhone distribution | Xcode source and unsigned Simulator artifacts only | No signed device IPA, TestFlight or physical-device certification. Apple signing route later, not obtained here |

## Repair, native links and actual UI verification — November8,2026,5:44 PM EST

- Actual097 real native whole-block MOVE/reopen/opaque-content test PASSES in
  42528695109. Separate original-color/back-stack test FAILS while sampling assumed
  AX-painted bounds; navigation assertions were not reached. Latest source retains
  exact original RGB tolerance, measures the actual3pt painted strip and surface,
  adds strict strip width and records real geometry before assertions. New pass
  still REQUIRED; no visual assertion is suppressed.
- Actual869 COMPLETE Apple core (nine purge cases included), mandatory original-web
  decoding/Go verifier and genuine universal Simulator build/package PASS in
  42530200596. Entire real native TLS orphan state/save/reload/delete/chunk404/local
  cleanup plus source-image/S3/backup-restore42530200601 is GREEN. All seven prior
  Unicode Apple tests also PASS at930. Original crypto/auth/wire unchanged.
- NEW repair state saves before upload, gates fresh referencing pushes, restores
  only exact authenticated original ciphertext/IDs, never overwrites a different
  existing ciphertext. Missing chunks can be restored; success receipt binds exact
  intent/revision so old/unrelated success cannot acknowledge a newer operation.
  Foreground native sync repairs ambiguous in-flight removals/references before
  outbound writes. No new production DELETE/UI is enabled. Full purge UI, fresh
  post-delete pull/retention policy and other-device/global-race boundary remain
  release gates. Real concurrent-reference-after-DELETE native TLS test added;
  latest Apple/live/network fault tests await new CI.
- Genuine native internal entry links/live local titles, accessible outgoing links,
  backlinks (original updated ordering/self/deleted rules), and honest missing/
  deleted/offline destinations implemented. Routing is LOCAL-ONLY, never a host
  derived from an entry ID; external links retain explicit confirmation. FOUR
  actual Foundation cases pass, mandatory original web docEntryLinks comparison
  and real UI/captures44–46 added, awaiting Apple verification. No link authoring
  picker or full inline-selection parity claim.
- TWENTY-THREE actual Foundation XCTest sync/purge/repair/link cases PASS. Existing
  30 browser checks and production TypeScript/Vite build PASS. Apple encrypted/
  transport/UI gates remain independently required. Related plain-editor/opaque
  mark NFC/NFD guards also now refuse unsafe normalization; no JSON schema change.
- Accessibility root cause (Apple run 42580870035, dd19955): the strict production
  XXXL audit FAILED while the identical full connection composition minus ONLY the
  two input fixedSize modifiers PASSED (normal and XXXL). Production inputs now use
  native sizing; the diagnostic seam/tests were removed. The strict normal production
  audit passed on dd19955 but failed on 869c075 with unchanged visible layout, so it
  is treated as unproven until it passes again. No audit is waived; re-verification pending.

<!-- Times are commit times in America/Los_Angeles; earlier labels this night ran ahead of the clock and were corrected. -->
## Day One archive parse and import run — November 9, 2026, 6:05 AM PST

These are local commits, not pushed yet. 13606df was pushed at 5:53 AM PST after Native 42627025025 was cancelled without ever getting a macOS runner. Native 42629435874 for 13606df is now queued.

- **26b9888 (5:59 AM PST): `DayOneArchive` ports `parseDayOneArchive`, `resolve` and `entryMoments`.** The parsed JSON stays a JavaScript-semantics value, so the web's behaviour carries over:
  - a `null` entry or moment, or a non-iterable `photos`, stops the import (the web throws a TypeError);
  - a string `photos` contributes nothing;
  - template strings print `undefined` and join arrays;
  - a `type` of `constructor` or `__proto__` resolves through `Object.prototype`, giving the Blob type the web would see;
  - durations round like `Math.round`.

  Names and keys are compared by exact UTF-16, so NFC and NFD duplicates stay separate and the Kelvin sign is not "K"; the ZIP reader's member order was corrected the same way. Not-a-zip and no-journal errors use the web's exact messages. Deliberate difference: media members are inflated only when attached, not all at once, so a large export fits in iPhone memory. A corrupt media member therefore fails at that point, with the same "not a valid .zip" message. The test has 9 fflate-built archives; mutating string iteration, `undefined` templates, NFC/NFD ordering, BOM handling and prototype types is caught.
- **51dfeab (6:05 AM PST): `ChapterDayOneImport.run` ports `importDayOne` behind `DayOneImportTarget`.**
  - Notebooks are matched by name using JavaScript lowercasing. That includes Greek final sigma, which Swift's `lowercased()` gets wrong; if two notebook names match, the later one wins.
  - New notebooks get the web's colours, covers, ids and "Imported from Day One" subtitle.
  - Each entry is created, then its labels are trimmed and deduplicated like the web's.
  - Media are attached one by one: consecutive images become a gallery, missing or refused files are counted as skipped, and progress is reported per entry.
  - `parseDate` follows V8's ISO date format: date-only means UTC, a date-time without an offset means local time, DST gaps and overlaps resolve like ECMAScript, 24:00 and Feb 30 roll over, and lowercase `t`/`z` and a space separator are accepted. V8's legacy, non-ISO formats fall back to the current time.

  The test replays 4 imports (one with 34 dates in Los Angeles time, 3 that stop partway) and compares every call with the web. Mutations to sigma, galleries, DST, labels, the hour/offset ranges, the `z` suffix and notebook matching are caught.
- **Gate:** core suite 169 tests, 0 failures; all native vectors; `tsc`; 30 of 30 web checks.
- **Next:** a VaultModel adapter (`createJournal`, entry create/update through the normal encrypted save, media through the upload queue), then the import sheet with the web's ImportDayOne strings and a UI test. Then markdown import.

## Day One import groundwork — November 9, 2026, 5:51 AM PST

These are local commits, not pushed yet: Native 42627025025 for 3453939 is still queued and must not be cancelled.

- **4086c7c (5:47 AM PST): Day One markdown.** `ChapterDayOne` ports the web importer's `markdownToBlocks`, `plainText`, `splitTitle` and moment URL parsing. JavaScript regex semantics are written out explicitly: `\s` is the ECMAScript whitespace set (with U+FEFF, without NEL), `\d` is `[0-9]`, and the title cap uses UTF-16 length. 29 documents and 14 moment URLs are compared against the web code in `dayone-markdown.json`.
- **ed36fed and 637307c (5:50 and 5:51 AM PST): ZIP reader.** `ChapterZipReader` is pure Swift. It reads the central directory (including ZIP64) and handles stored and deflated members with an RFC 1951 inflate. It lists members in fflate `unzipSync` order, so a repeated name keeps its last copy. Each archive is built by fflate `zipSync` at levels 0, 1, 6 and 9 with a fixed mtime, so the fixtures are reproducible. One file (`varied.bin`) covers every length and distance band. Mutating the length table, the distance extra bits or the stored-block length is caught.
- **Gate:** core suite 165 tests, 0 failures; all native vectors pass; `tsc`; 30 of 30 web checks.
- **Next:** port `parseDayOneArchive`, `entryMoments` and the run orchestration (match journals by name or create them, galleries, media through the upload queue), then the import sheet with a UI test.

## Export a journal from Settings — November 9, 2026, 5:43 AM PST

- **33f506b (5:43 AM PST):** Settings → Your data → Export a journal. Like the web sheet, it has a pick step (notebooks with entries and their counts), a working step (the web progress steps), a done step (the filename and the entries, media and missing-media counts) and an error step.
  - Instead of the browser download, the archive goes to the iOS share sheet: Save to Files, AirDrop or another app. The web's three lines about "downloads" are replaced by honest native English; every other line uses the web's own translations.
  - The core now streams (`ChapterExport.writeZip`), off the main actor. Media is held one file at a time; locking the vault aborts the export and deletes the partial file.
  - The progress sequence equals the web `onProgress` steps, and the reverse-leg zip comes from `writeZip` itself.
  - New UI test `testExportBuildsTheWebArchiveAndOffersItToShareLikeTheWeb`, with strict audits on the picker and the summary.
- Committed locally only: Native run 42627025025 on 3453939 has been queued since 5:36 AM PST.

## Apple run on e30d301: Simulator build fixed; export markdown — November 9, 2026, 5:36 AM PST

- **Native run 42623798125 (e30d301)** got a runner at 5:20 AM PST and failed at 5:30 AM PST in "Build genuine native app for iOS Simulator". The native core tests step passed. These were two real compile errors in app code the Linux core build never compiles; the last successful Simulator build was e825899:
  - `WritingStatsSection.body` mutated a local (`utc.timeZone = …`) inside a `@ViewBuilder`. It is now built in a closure.
  - The free functions `badgeName` and `badgeDesc` called the main-actor `VaultModel.t` from a nonisolated context. They are now `@MainActor`.
  - I reviewed every app line added since e825899 against the declarations it uses (Equatable `onChange` values, iOS 17 APIs, Identifiable `ForEach` data, return types) and found nothing else. The UI tests have not run on Apple since then.
  - Fix: 4079b36 (5:36 AM PST).
- **aeaa507 (5:36 AM PST), export markdown:**
  - `ChapterMarkdown` ports the web `docToMarkdown`, including every way the web serializer throws (the export then uses the entry text, like `safeMarkdown`).
  - `JSValue` ports JavaScript `JSON.parse` and `JSON.stringify` for the `mneme:*` fences: strict grammar, first-position duplicate keys, index keys first, `Number::toString`, escapes.
  - Covered by 153 web cases: 112 render, 18 throw and 19 are rejected by JSON.parse. Mutations (fence length, URL scheme whitespace) are caught.
  - One documented difference: a lone UTF-16 surrogate becomes U+FFFD, as everywhere a vault record is decoded.
  - The `parseDoc` fallback now splits on `\n` alone, like JavaScript, where Swift had split `\r\n` as one character.

## Web export fix: media without a saved date — November 9, 2026, 5:27 AM PST

- `ArchiveWriter.add` (web `src/export/journal.ts`) now gives the export time as the zip time to any file whose own time falls outside 1980–2099 in local time, fflate's limit. Nothing else changes: the manifest and entry JSON keep exactly the dates they always wrote (for example `1970-01-01T00:00:00.000Z`), in-range times are kept, and a non-numeric time is left to fflate as before.
- Regression check `checkUndatedMedia` in `scripts/export-journal.ts` covers a gallery image with no date, media dated 0, an entry with `updatedAt` -1 and a dated control. It reads the zip times from the central directory. It fails with the original error without the fix, and passes in the UTC, UTC+14 and UTC−11 time zones.
- The native `ChapterZipWriter` uses the same rule: a local 1980–2099 range, falling back to the export time.

## Interview types and journal export core — November 9, 2026, 5:24 AM PST

- **b1001b1 (5:18 AM PST), interview types:** a native manager matching the web InterviewTypesSheet, opened from Settings → Assistant. It covers the 15 built-ins, create, edit and delete. A built-in forks only on a real change; deleting one writes a tombstoned fork. Covered by web-generated wire-body vectors plus UI test `testInterviewTypesAreManagedLikeTheWebInterviewTypesSheet` (still to run on Apple).
- **6a549c5 (5:24 AM PST), export core:**
  - `ChapterExport` ports the web export/journal.ts and collect.ts: entry selection and order, `parseDoc`, inline media (`coerce`) and legacy attachments, path deduplication, `safeId` and extensions, ISO dates, `slugify` (NFKD), the manifest and the README.
  - `ChapterZipWriter` streams a store-only zip.
  - Verified both ways against the real web code, and a mutation is caught.
  - Not yet: markdown, the export button and share sheet, and import.
- **Web bug found:** the web `exportJournal` threw `date not in range 1980-2099` (fflate) when an inline media node had no `createdAt`, because it was coerced to 0, i.e. 1970. An entry `updatedAt` out of that range did the same. Fixed with your approval (see the next section).
- **Apple:** Native run 42623798125 on e30d301 got a runner this time and is in progress, so both commits stay local until it finishes.

## Search and badges — November 9, 2026, 5:09 AM PST

Committed locally while Native run 42621358291 (d0cca2f) was queued. That run also got no macOS runner: GitHub cancelled it at 5:12 AM PST with the same "not acquired by Runner" annotation. On the same revision, the macOS live-relay job did get a runner (5:08 to 5:10 AM PST) and passed. That is the native TLS/Go/Postgres relay round trip; the native unit and UI suites did not run. These commits were pushed once as a batch afterwards.
- **7fbe254 (5:04 AM PST), search:** a port of the web search/core and the Search sheet. Every word must match the title, labels, the entry date or the body. Results are ranked title, then label, then date, then content, newest first, up to 50, and the matched field is tagged.
  - Dates match in local time, written in English and in the active language ("jun 9", "9. Juni 2026", "2026-06-09", "9.6.2026").
  - Matching is on UTF-16 code units after JavaScript toLowerCase, including the Greek final sigma.
  - For exact vectors, the web's `searchHits` and `toEnglishMonths` are now exported from `ui/Search.tsx` (same behavior), and month names come from the web `monthName()`.
  - 456 web-generated queries in 12 languages pass; two deliberate mutations are caught.
  - The entry list uses the web placeholder, field tag, snippet and empty text.
- **964cd01 (5:09 AM PST), badges:** a port of state/badges.ts.
  - The eight rules ignore tutorial seeds and deleted entries. A mention of a video node doesn't count, and media needs real ids.
  - Interview-type names are the synced live records plus the built-in seeds not yet forked.
  - The celebrated set is stored on the device per owner (`mneme.badges.seen.<owner>`), with the web's quiet first-run catch-up.
  - Settings shows the gallery, and newly earned badges celebrate one at a time.
  - Vectors cover 22 vaults and 21 catch-up cases. Public fixtures start from the quiet catch-up so a celebration never covers another test.

Local results: core 159 tests (3 skipped, 0 failures), all vectors, tsc and 30/30 web checks.

## Batch for Apple: stats, calendar, journals, built-in templates — November 9, 2026, 4:56 AM PST

**Apple run 42619097145 (fd0dbdf) did not run.** No macOS runner picked up either macOS job (Native iOS and the native live relay) in 15 minutes. GitHub cancelled both at 4:56 AM PST with "The job was not acquired by Runner of type hosted even after multiple attempts" and a notice about macOS arm64 capacity. No test ran, so there were no failures to fix, and everything pending since fd0dbdf is still unverified on Apple. The Linux jobs passed (CI, package-and-clean-stack).

Committed locally while waiting, then pushed together:
- **a9c2fd5 (4:44 AM PST), built-in template bodies:** "Edit template" on a built-in opens the rich editor. The first applied change forks the seed like the web mutateSeeded; leaving without saving forks nothing.
- **a996a1c (4:48 AM PST), writing stats:** the six Preferences "Your writing" tiles, from a port of state/stats.ts. This covers UTC days, JavaScript whitespace word counts and the exact toFixed(1) compact counts, all checked against web-generated vectors.
- **19854af (4:51 AM PST), calendar:** On this day, the empty-day text and the 17-week heatmap with the web colors and `tp('calendar.weeks')`. This also fixes the accent-ink, accent-soft and accent-line colors: they previously fell back to the paper color, which made the location-card pin invisible. They now come from the palette exactly as in the web useTheme, checked for every palette.
- **abe0ddd (4:55 AM PST), journals:** the web New journal sheet (name, color swatches, cover, Start from) and the Edit journal sheet's swatches, Save changes and untitled fallback.
- **6cf23de (4:56 AM PST), localization:** Edit, Save, Cancel, "Link to entry" and Table use the web keys. The strings check now also verifies plural `tp()` keys; native screens use 79 keys, and all exist in the web catalog.

Local results before the push: core 157 tests (3 skipped, 0 failures), all vectors, tsc and 30/30 web checks.

## Apple run on e825899 and fixes — November 9, 2026, 4:40 AM PST

Apple run 42614136563 (e825899):
- **Core:** 152 passed, 2 skipped, 0 failed. This includes KaTeX output equal to the web's, the interface strings in 12 languages, and multi-run formatting. The Swift ciphertext, the web decoder, the Go verifier and the Simulator build all pass.
- **UI tests:** 34 passed, 8 failed. Passing: math typesetting, format across runs, table commands (the reveal fix), the language and built-in template tests, and every other functional test.

The eight failures had three causes, all fixed in 7f6b820 (4:40 AM PST):
- **Lazy rows:** cb396b2 put the "Format across runs" section above the text runs. The list loads rows lazily, so five rich-editor tests and one page capture could not find `rich.run.0/0`. The section now sits below the runs.
- **Connection-screen audits:** both strict audits still reported "Dynamic Type font sizes are unsupported" with no element named, even after the d59bab7 row-growth fix. The bisected cause was long wrapping rows in a Form, and a Form is a lazy list: once those rows outgrow the screen, cells leave the hierarchy while the audit resizes text. The screen is now a non-lazy ScrollView of grouped cards. Both strict audits stay required.
- **Location card audit:** the card itself passed. The audit flagged "Hit area is too small" on the one-line paragraph "Public walk", because selectable text is an interactive element. Rendered blocks are no longer individually selectable; the entry's actions offer "Select text", one large selectable block with Copy (web `common.copy`).

Committed locally while the run was in progress, and pushed together after it finished:
- **9e9cd13 (4:09 AM PST), localization wave 1:** tabs, settings, appearance, shared actions, template and table actions use the web keys.
- **eaeb9d1 (4:15 AM PST), template bodies:** edited with the rich editor, like the web TemplateEditor.
- **23dbeaf (4:16 AM PST), localization wave 2:** entry, notebook and calendar screens.
- **Checks:** the strings check fails if the app uses any key missing from the web catalog (57 keys used). The new UI test covers German and Arabic with the strict audit.

Local results before the push: core 155 tests (3 skipped, 0 failures), all vectors, tsc and 30/30 web checks.

## Interface text and location cards — November 9, 2026, 4:05 AM PST

Commit e825899.

- **Interface text:** the app now ships the web's own message catalogs (860 keys in 12 languages, copied by `scripts/native-ui-strings-vectors.ts` and checked byte-for-byte). It also has ports of the web's `t()` (lookup, English fallback, `{name}` filling), `tp()` (CLDR plural categories, including French, Spanish and Italian "many" and the six Arabic forms) and `fmtNumber`. Native does its own half-expand rounding and CLDR grouping (Spanish and Italian 4-digit numbers, Hindi lakh grouping, French narrow no-break space), so Apple and Linux formatter differences can't leak in. The local test checks every sampled key, every plural base at 17 counts and the number and distance cases in all 12 languages.
- **Location cards:** a valid `locationMap` node now renders as the web's card. The map and optional travel photo are decrypted through the existing encrypted media path; the plaintext temp file is deleted right after it is read. The card shows "from → to" labels with the catalog fallbacks, the web's distance formatting, and the web's aspect ratio (600/340 by default). No third-party map tiles are requested.
- **Divergence:** a card missing its coordinates or map keeps the visible marker, where the web shows nothing. Stored data is never hidden.
- **New UI test:** `testLocationCardDecryptsItsMapOfflineAndUsesTheWebsGermanText` uses a really encrypted public map and checks the German text plus the strict audit.
- **Local results:** core 154 tests (3 skipped, 0 failures), all vectors, tsc and 30/30 web checks.
- **Pending on Apple:** this UI test, the math tests from 626e0ed (3:58 AM PST), and the connection-screen and table fixes from d59bab7.

## Apple run on 0ca803f and connection-screen fix — November 9, 2026, 3:49 AM PST

Native run 42607615562 (0ca803f): all 140 core tests passed on Apple (including
RichTableEditTests and ChapterLocaleTests); strict vector steps passed (selection
23/23, table editing 24/24, built-ins in all 12 locales). New UI tests passed:
selection formatting, built-in templates, language choice, cursor insertion and the
template manager. The temporary bisection isolated the connection-screen finding:
only the variant adding a long wrapping body Text row to the passing Form reproduced
"Dynamic Type font sizes are partially unsupported". d59bab7 makes every wrapping
text row on the connection screen grow vertically and removes the bisection view,
launch flag and test. The table UI test now reveals the off-screen Delete table row
(the only other failure). Both strict production audits remain required and must
pass on the next run. bdadc98 fixes a pre-existing millisecond timing flake in the
template-rename test (one fixed instant for both compared renames).

Local verification before every push: the full ChapterCore suite (146 tests) now
runs on Linux with test-only shims, and its native outputs pass the same strict
web decoder/TipTap checks CI runs. Apple remains the authority for SwiftUI, UI
tests and audits.

## Multi-run formatting — November 9, 2026, 3:30 AM PST

cb396b2: Format across runs (iOS 18) selects text that spans several differently
formatted runs of a paragraph or heading and applies the original toolbar's
toggleMark over that range: TipTap isMarkActive coverage (marked text plus text
whose marks exclude the mark), canSetMark, ProseMirror addMark/removeMark over every
inline node (entry links and math included) and fragment joining. 25 cases are
generated by the real TipTap Editor; the native output also passes the strict web
schema check; 6/6 mutants are killed. Native refuses rather than guesses: surrogate
splits, code blocks, no-op toggles and adding code over links or unknown marks.
Typing in that view is ignored, so a selection always refers to the saved text;
words are still edited per run.

## Apple run on a71a314 — November 9, 2026, 3:14 AM PST

Native run 42605056777 stopped in core tests. `testFormattingRetainsOpaqueMarksAndCodeFollowsOriginalSchema` failed because d986a6b re-sorted whole mark sets, which moved an unknown future mark behind the known ones. The test correctly requires that native formatting never reorders existing marks.

The fix follows ProseMirror's `Mark.addToSet`: a new mark goes before the first existing mark of higher schema rank, and nothing else moves. Whole-run and selection formatting both use it, and the selection fixtures still match TipTap on all 23 cases.

That test now also runs in the Linux harness (51 tests pass). The d561af7 run also showed that ChapterLocaleTests looked for the catalog in the test bundle. It ships in ChapterCore's own resources, so the tests now use `ChapterLocales.bundled`, as EntryTemplateTests uses `BuiltinTemplates.bundled`. RichSelectionTests passed on Apple in that run. Because core stopped the run, the UI steps, and with them the connection bisection, didn't run, so the bisection result comes from the next run.

## Table editing — November 9, 2026, 3:11 AM PST

The original table toolbar's six commands (add row below, add column right, delete row, delete column, toggle header row, delete table) now work natively. In the rich editor, **Tables → Table N** opens a grid: choose the cell the cursor would be in, then run the command.

**What matches prosemirror-tables exactly:**
- **New cells** take their type from the neighbouring row or column, using `addRow`/`addColumn`'s header-row and header-column rules.
- **Header toggling** skips the corner when the first column is a header column. Cells keep their attrs and content.
- **Deleting the only row or column** does nothing on the web and is refused natively.
- **Deleting a table** that was a container's only child leaves the empty paragraph ProseMirror inserts.
- **Column widths:** after every table command, the `computeMap` width vote and `findBadColWidths` run as `fixTables` does, so a column's width spreads to cells that lack it.

**Kept unchanged:** the fields of rows, cells and the table itself.

**Refused, not approximated:** merged-cell, ragged or malformed tables. They stay read-only natively and are preserved exactly.

**Ground truth:** `rich-table-edit.json` comes from the real TipTap Editor with the original extensions, with the cursor placed in the chosen cell. Its 24 cases include header rows and columns, a single-cell table, a table nested in a quote, and a conflicting-width vote. Every native output is re-checked through the real web schema.

**Results:** 50 local tests pass, and 7 of 7 deliberately introduced bugs were caught. `testTableToolbarCommandsRestructureAnOriginalTable` starts an entry from the original Experiment log built-in, adds a row and a column, deletes the column, then deletes the table with confirmation (native has no undo).

## Languages and localized built-in templates — November 9, 2026, 3:02 AM PST

The original web's language is a device-only choice that never syncs: `mneme.locale`, English by default, 12 languages. Pristine built-in templates re-render in that language, and the first rename or delete forks the text being shown. Natively:
- **Settings → Language** offers the same 12 languages by endonym and stores the choice in this device's UserDefaults; it never syncs. As in the original `initI18n`, an unknown or missing choice means English.
- **Built-in templates** show in the chosen language. Forking keeps the shown language, as on the web.
- **Arabic flips the layout to right-to-left**, and dates follow the chosen language. English leaves the device's regional formatting alone.
- Other native interface text is still English.

**Ground truth:** `builtin-templates-locales.json` is generated by the web's own `setLocale` and `seedBuiltinTemplates`, loaded through Vite SSR so `import.meta.glob` expands exactly as in the bundle (no server listens). It is re-verified on every vectors run, and its English entries must equal the bundled English seeds.

**Checks:** native preview text equals the web's `docToText` for all 72 localized seeds (12 locales × 6 templates). A catalog with a missing language or reordered slugs is refused. 46 local tests pass.

**UI test:** `testOriginalLanguageChoiceLocalizesBuiltinTemplatesLikeTheWeb` switches to Deutsch, sees "Tagesrückblick" and starts an entry with "Wie sich der Tag anfühlte". Public fixtures always start in English, so the choice can't leak into other tests.

## Apple results for e363f81 — November 9, 2026, 2:57 AM PST

Native run 42600255378:
- **Passed:** `testLargestDynamicTypeControlGeometry` (the slow, two-way reveal works), the XXXL SecureField and full-width CTA reproductions, `testCursorInsertsOriginalLinkAndTemplateAtTheCaret`, the template manager test and every other functional test. Core (RichCaretTests, EntryTemplateTests) and the web cross-checks pass. Server/live and CI are green. The contrast finding is gone.
- **Still failing:** both strict connection audits, on a single "Dynamic Type font sizes are partially unsupported" element with no name. Every isolated component passes on its own (Form, SecureField, CTA, all at normal size and XXXL). A temporary Debug-only bisection, `testConnectionAuditVariantsIsolateTheProductionDifference`, adds exactly one production difference to the passing Form per variant: paper navigation-bar surface, header rows, sections, privacy-sensitive SecureField, field modifiers, the production CTA inset, keyboard dismissal, footnotes. Every finding is still recorded as a failure. It will be removed once the cause is fixed.
- **Built-in template test:** the weekly actions button was on screen but never reported hittable, and the slow swipes didn't move the sheet's list. It now waits for the control and taps it directly, as the passing template manager test does; XCUITest's tap still fails if the control can't be reached.

## Formatting selected text — November 9, 2026, 2:30 AM PST

The original toolbar runs TipTap `toggleMark` over the selection. On iOS 18 the native editor now tracks a selected range in the run being edited, and Bold, Italic, Underline, Strikethrough and Inline code apply to just that range:
- **The mark is removed if the run already has it, otherwise added.** Within one text node this is exactly TipTap's `isMarkActive`.
- **Mark sets follow the original schema's rank order** (link, bold, code, italic, strike, underline). Whole-run formatting now writes them in that order too, rather than appending.
- **Inline code excludes every other mark, as in the original.** Adding code drops bold, italic, strike and underline. Native refuses where code would silently erase a link or another non-native mark.
- **Split pieces keep every original field.** Equal-mark neighbours join at the seams with the left node's fields, like ProseMirror's `addNode`.
- **Refused:** splitting inside a surrogate pair, code blocks, and cases where the web makes no change (for example bold inside inline code), rather than writing a no-op.

Typing over a selected part of the run replaces it with the run's own marks. Within one text node that equals ProseMirror `insertText`'s `marksAcross`.

**Ground truth:** `rich-selection.json` comes from a real TipTap Editor with the original extensions, run headless in jsdom. The generator asserts that loading the document changed nothing. The 23 cases cover splits, joins on either or both sides, rank order, code exclusion, emoji, links, entry links, hard breaks, lists, tables and code blocks. The schema's mark rank and exclusions are also checked against the Swift tables, and every native output is re-checked through the real web schema.

**Results:** 43 local tests pass, and 5 of 5 deliberately introduced bugs were caught.

**UI:** the formatting controls now sit below the editor, so the system edit menu over a selection can't cover them. `testSelectionFormattingAppliesOnlyToSelectedTextLikeOriginalToolbar` selects "Public" in the bold heading and removes bold from that word only.

## Apple results for 55a66dc (run on 3bcde6e) — November 9, 2026, 2:21 AM PST

Native run 42596110804. GitHub created no runs for 55a66dc itself; an empty commit re-triggered them.
- **Normal-size connection audit:** the Dynamic Type finding is **gone** (moving the text into ordinary rows worked). The remaining finding is "Contrast nearly passed", caused by the `.secondary` grey footnotes added in 55a66dc. Fixed by restoring the full ink colour.
- **XXXL audit:** still "Dynamic Type font sizes are partially unsupported", on the very first audit at the top of the screen. Neither the log nor the xcresult names the element. The unmodified Form reproduction passes at XXXL, but the SecureField and full-width-CTA reproductions had only been audited at normal size, so both now also run at XXXL in the required large-type step to tell them apart.
- **XXXL geometry test and the built-in template UI test:** both failed in the test helper. A fast `swipeUp` flung the tall XXXL rows past the viewport (the hierarchy shows the list at 100% with the server field scrolled past). `reveal` now drags slowly and searches both directions; reachability is still required.
- **Everything else passed:** all other functional UI tests, including `testNativeTemplateCreateRenameAndDeleteLikeOriginalManager`, plus core, the web vectors (template authoring, built-in seeds) and server/live.

## Cursor tracking: insert links and templates at the cursor — November 9, 2026, 1:56 AM PST

- **Cursor model:** `RichCaret` is ProseMirror's own cursor form: a textblock path plus a parent offset (UTF-16 units; each non-text inline node counts 1). `caret(leaf:utf16Offset:)` maps the native editor's cursor in a text run, or in an empty block, onto the original document. It refuses offsets that would split a surrogate pair or fall outside the run.
- **Entry links:** `insertInline` follows TipTap `insertContentAt` → ProseMirror `replaceWith`. It splits the text node and keeps all of its marks and fields on both halves, inserts `[entryLink, " "]` exactly as wikilink `insertEntryLink` does, and joins the trailing space into an unmarked neighbour as ProseMirror does. It refuses code blocks, and refuses text-first content (TipTap's separate `insertText` path).
- **Templates:** `insertBlocks` follows Editor `insertTemplate` at a top-level paragraph or heading. An empty block is replaced; at the start the blocks go before; otherwise the block splits and an empty half is dropped, with no joining. Nested positions are refused rather than guessed.
- **Evidence:** 21 cases generated by the **real ProseMirror transform**, mirroring `insertContentAt`, with marks, link marks, hard breaks, existing links, an emoji ZWJ sequence, a list item, a table cell and headings. Native output equals all 21; the vectors step re-checks it strictly through the real web schema. 38 local Foundation tests pass; 4/4 deliberate mutations caught. A fifth surviving mutation exposed dead code, which was removed.
- **UI (iOS 18):** the run editor tracks the cursor (`TextEditor` selection) and offers "Insert link here" and "Insert template here". Pending text is saved first, so the cursor refers to what you see. Both edits are compare-and-set on the exact document bytes. On iOS 17 the actions are not shown, and link-at-end stays available. Apple UI test `testCursorInsertsOriginalLinkAndTemplateAtTheCaret` is pending.
- **Not yet:** formatting a selected range, or replacing a selection.

## Apple results for cd787e8; real Dynamic Type element found — November 9, 2026, 1:31 AM PST

- **Audits on Native 42591403122 (cd787e8):** the strict audits still failed, but the finding changed from "unsupported" (no element) to "**partially** unsupported", and the audit now attaches the element. That element was the system Section **footer** (phrase note) in the normal audit and the system Section **header** "UNLOCK VAULT" at XXXL.
- **What that rules in and out:** the fields with overriding labels and the fixedSize rows were the earlier full failure. Here the remaining failing elements were only the system header/footer text, which apparently grows only part of the way.
- **Fix:** all connection text is now ordinary Form rows in scaling text styles (title2, body, headline with the header trait, footnote secondary), with no fixedSize and no system header/footer. The audit stays strict: three fresh launches at the normal size plus XXXL.

## Original built-in templates — November 9, 2026, 1:19 AM PST

- **Seeds:** the six web seeds (Daily reflection, Three small things, Dream log, Experiment log, Study notes, Weekly review) ship as `Resources/builtin-templates.json`. The real web `seedBuiltinTemplates` generates that file, and the vectors script re-verifies it on every run. The native preview text equals the web `docToText` for all six, including the table and task lists.
- **Local-only like the web:** like the web's pristine seeds, they are never stored or pushed until edited.
- **Retirement:** a seed is retired exactly as `supersedeBuiltinSeeds` does it, when any synced template, live or tombstoned, carries its slug.
- **Fork on first change:** a rename or delete forks the seed (web `mutateSeeded`) into a synced record carrying the `builtin` slug, so other devices retire their own seed. Difference from the web: native has no stored seed time, so `createdAt` is the fork time.
- **Language:** English only until locales land.
- **Evidence:** 35 local Foundation tests pass; 3/3 deliberate mutations caught. Apple UI test `testOriginalBuiltinTemplatesStartEntriesAndDeleteForksSyncedTombstone` is pending.

## Native template manager: create, rename, delete — November 9, 2026, 1:16 AM PST

Mirrors the original web TemplatesSheet / TemplateEditorView / createTemplate / updateTemplate / deleteTemplate:
- **Create:** name saved as ECMAScript `trim()` or "Untitled template". The record has exactly the original `templateCodec` fields (kind, name, bodyText, bodyJson, createdAt = updatedAt); `builtin` stays absent. An untouched body keeps bodyJson absent and bodyText "" (web `json || undefined`). The native body is plain paragraphs; rich template bodies are still edited on the web.
- **Rename:** only `name` and `updatedAt` and the clock change. Body bytes, the builtin slug and unknown future fields are preserved. A stale editor value is refused; a no-op rename does not advance the clock.
- **Delete:** a synced tombstone keeping every field, with a confirmation step like the web's armed delete. Entries already started from the template are unaffected.
- **UI:** "Start from template" (now shown whenever a notebook exists) gains New template, plus a per-row actions menu with Rename and Delete.
- **Evidence:** 34 local Foundation tests pass; 4/4 deliberate mutations caught (no trim, no stale check, no-op advancing the clock, tombstone wiping the body). The vectors script verifies the native template against the real web schema and `docToText`, and passed locally on the native output. Apple UI test `testNativeTemplateCreateRenameAndDeleteLikeOriginalManager` is pending.

## Connection-screen Dynamic Type fix; bisection removed — November 9, 2026, 1:10 AM PST

Apple run 42588998288 (ada486d) results:
- Table UI test `testOriginalTableRendersExactMergedGridWithHeaderAndAccessibleCells`: **passed**, along with all functional, link-picker, card-color and core tests (RichTableTests too), and the web cross-check step.
- The two strict connection audits still failed ("Dynamic Type font sizes are unsupported", 2 issues, no element given).
- The non-gating bisection reported a **3/3** failure rate for the baseline and for every variant: no toolbar background, no bottom action, no navigation title, no privacy overlay. The finding is deterministic, and none of those four is the cause.
- The unmodified native Form, SecureField and full-width-action reproductions pass under the same root modifiers (appearance style, privacy, tint). So the cause is inside the connection Form's own content.

Fix (production, not verified on Apple yet):
- ConnectView now uses the native Form pattern: Section `header:` and `footer:` with system styles in place of hand-built header and footnote rows using `fixedSize`.
- The fields no longer get explicit `.font(.body)` or accessibility labels that override their placeholder. The SecureField placeholder is now "12-word recovery phrase", so the visible text and the spoken label are the same.
- Removed every diagnostic seam: `chapterDiagnostic`, the `ChapterScreenSurface(navigationBar:)` variant, the `ChapterAccessibilityBisection` test class, and the workflow step and its skip.
- The required normal audit is now **stricter**: it audits three fresh launches, and every finding still fails the test. No audit was weakened or suppressed.

## Custom-block markers match the original preview — November 9, 2026, 12:56 AM PST

- Location and video-interview blocks now use the original DocPreview labels and
  truthiness (`📍 from||Location[ → to]`, `🎬 name||Video interview[ · N
  question(s)]`) in the original marker style (UI face, ink-3, dashed line,
  radius 9). Fixes the previous native "Location → " with an empty destination.
  1 new Foundation test (33 total) PASS; UI label checks pending Apple. Maps,
  clips and math are still not rendered as images/KaTeX natively.

## Native "start from template" — November 9, 2026, 12:55 AM PST

- Journal → New from template lists synced templates (name || "Untitled
  template", text preview) and a notebook picker. Use mirrors the original web
  newEntryFromTemplate/createEntry: the template's EXACT bodyJson/bodyText strings
  (byte-for-byte, opaque nodes and NFD kept), title = original defaultEntryTitle
  (local `YYYY-MM-DD HH:MM:SS`), empty labels, only the original entry fields.
- `entry-titles.json` is generated from the REAL web defaultEntryTitle across 4
  time zones (incl. DST and +12:45); 3 new Foundation tests (32 total) PASS locally.
  New UI test (opens the new entry, checks heading/prompt/title format/table)
  pending Apple verification.
- Not yet: creating/editing templates natively, inserting a template into an
  existing entry at the cursor, and the web's local-only built-in seeds (those
  appear natively once edited on the web, because only then are they synced).

## Apple results for 7bee115 and accessibility bisection — November 9, 2026, 12:51 AM PST

- Native 42584833292: complete Apple core, the mandatory web vectors step (now
  including the native link-insertion schema/collector/preview cross-check), the
  Simulator build, page captures and ALL functional UI tests PASS, including the
  new native link picker test and the XXXL layout/geometry test.
- Both strict production connection audits FAILED again (“Dynamic Type font sizes
  are unsupported”, element unresolvable). The e1eaf4d fixedSize hypothesis is
  DISPROVEN: production now matches the earlier passing diagnostic, and the normal
  audit has gone fail → pass → fail with no layout change, so the finding is
  intermittent. The earlier diagnostic audited once at launch, which is why a
  single pass misled. Recording frames show every content text scaling during the
  audit; the culprit is not visible, so the next CI run carries a NON-GATING
  bisection (3 fresh audits each: baseline, without nav-bar toolbar background,
  without bottom action inset, without nav title, without privacy overlay). Seams
  are DEBUG-only; release behavior is unchanged. Strict audits remain required.

## Original tables rendered as the exact merged grid — November 9, 2026, 12:22 AM PST

- New core `RichTableLayout` mirrors the actual prosemirror-tables `findWidth`/
  `computeMap`: colspan, rowspan, collisions, overlong rowspans, missing and zero-
  sized tables. 9 table cases are generated from the REAL web schema + `TableMap`
  (`rich-tables.json`, verified on every CI run); native map/problems equal them.
  3 new Foundation tests (29 total) PASS locally and catch 4/4 deliberate mutations.
- Native rendering places each original cell over its exact rectangle using web
  table styling (1pt `line` border, header `surface-2` + semibold, 7×10 padding,
  UI face), honors agreed TipTap colwidth, and labels every cell with row/column/
  span for VoiceOver. Fractional/zero/huge spans or non-cell children keep the
  honest simplified fallback. Read-only: no table editing; `findBadColWidths`
  width repair is not emulated (conflicting widths show natural widths).
- New UI test for header/merged geometry pending Apple verification.

## Native entry-link authoring — November 9, 2026, 12:17 AM PST

- More → Link to another entry: picker mirrors original web `[[` filtering/order/
  limit; inserts the exact original entryLink node (+ trailing space) as a new
  paragraph with byte-exact compare-and-set. 3 new Foundation tests (26 total)
  PASS locally and catch 4/4 deliberate mutations; the real web TipTap schema,
  docEntryLinks and docToText accept the native output unchanged (local check,
  mandatory on Apple CI). New functional UI test pending Apple verification.
  Cursor-position insertion remains unimplemented.

## Apple verification of dd19955 — November 9, 2026, 12:11 AM PST

- Live TLS/Postgres/S3 relay (42580870048) GREEN, including the new concurrent
  reference-after-DELETE repair restoring byte-identical original ciphertext.
- Native functional UI: ALL functional tests PASS, including native entry links/
  backlinks without network, honest missing/offline target, corrected journal card
  original-color pixel test, Arrange reordering, and page captures 44–46.
- Remaining native failure: strict XXXL production audit (fixed above, pending).
  Professional whole-app fidelity, missing native groups and signed physical iPhone
  delivery NOT complete. Destructive media removal remains unexposed in UI.

## Guarded media-removal increment — November8,2026,5:27 PM EST

Real core queued/sending/confirmed/cancel/finish lifecycle now retains intent in
existing encrypted local opaque recovery, with exact whole-snapshot review CAS,
shared/deleted/recovery/pending/opaque-schema protections and guarded idempotent
physical ciphertext cleanup. SEVEN actual Foundation XCTest cases PASS (13 with
six sync regressions); TWO additional Apple AES/file fault/restart tests and the
extended actual native TLS orphan lifecycle await CI. **No destructive production
UI or automatic drain is enabled; media-removal parity is NOT complete.** Fresh
pull plus in-flight reference repair/other-device boundary/explicit UI remain
required. See CHAPTER-MEDIA-PURGE.md. No crypto/wire/local schema change.

Latest097 actual dedicated page tour PASSES:5 tests,0 failures,0 skipped. Genuine
Journal/Calendar original-style cards, filtered notebook/cover and Arrange pages
were visually inspected from same-build captures at5:18–5:21 PM EST. This is NOT
certification of the independent RGB/back-stack/reorder assertions or full visual
parity. Actual5b normal/XXXL strict Dynamic Type audits still FAIL; latest097
normal production/comparison audit step also FAILS, exact isolated CTA outcome
still to inspect. No audit is suppressed. Original six bundled fonts remain.
Screenshot inspection caught singular-count copy; source fixes "1 entries" to
"1 entry" without retouching evidence. Physical iPhone delivery remains incomplete.

## Byte-exact sync correctness — November8,2026,5:20 PM EST

Actual compiled pre-fix production source reproduced an NFC acknowledgement
incorrectly clearing an unsynced NFD edit at the same clock. Sync now compares
stable original JSON bytes (including opaque nested values/object-key spelling),
not Swift canonical String equality. Recovery deduplication retains both distinct
versions; equal-clock differing server values are retained even when local was
already clean. Exact matching lost acknowledgements still clear dirty. Nonfinite/
non-encodable payloads never acknowledge successfully. Notebook Unicode-only
renames now advance an actual edit instead of silently no-oping.

SIX actual Linux XCTest cases against production Foundation source PASS. A seventh
real Apple AES encrypted snapshot/cursor/disk-fault/reopen/retry test is added and
REQUIRED in native CI, not yet verified. Original server crypto/schema unchanged.
This does not establish simultaneous duplicate canonical JSON object-key support:
Swift Dictionary cannot hold both equivalent keys in a single object.

## Verified increment — November8,2026,5:09 PM EST

- At5b2ac8f, complete actual Apple core suite PASS, including SIX new whole-block
  structure/Unicode/adversarial/draft-media preservation/encrypted disk-fault and
  reopen tests plus strict original DELETE status/ID/token tests. Mandatory real
  Swift-authored reordered ciphertext→original web decoder, original Go verifier,
  genuine universal Simulator app build and package PASS in42528312711.
  Actual new Arrange screen interaction/capture still verifies independently.
- ENTIRE genuine native trusted TLS/Go/Postgres plus Chapter source-image/S3/
  backup-restore42528312708 SUCCESS at5b2ac8f. New actual native orphan media
  delete verifies both index and every encrypted chunk return404, idempotent
  retry and unchanged unrelated shared/recovery media. Storage-failure injection
  is separately actual Go memory-store unit coverage, NOT a live S3 outage test.
- Strengthened1acd4dd real media/page tour42527124109 PASS: official Xcode JSON
  reports5 tests,0 failures,0 skipped. Genuine decrypted text actually rendered
  in Quick Look and true Done dismissal completed before navigation. Actual
  preview screenshot visually inspected at5:00 PM EST. Photos39 still a loading
  frame, not certified imported-photo/picker playback.
- Latest097e45c source adds genuine original-style cards/native notebook back
  navigation plus strict isolated CTA diagnosis. Its new app/build/RGB/back-stack
  screen gates are pending; passing earlier5b does NOT certify these later edits.
- Production normal/XXXL Dynamic Type and intermittent XXXL reachability remain
  open release blockers. Full visual/usability inventory and device signing remain
  acceptance gates, not replaced by passing core or screenshot assertions.

## Original-card fidelity and native notebook navigation increment

Source-grounded shared cards now use original surface/line tokens,14pt radius,
3pt notebook-colored leading edge and original typography in Journal/Calendar.
Removed nested NavigationStack from pushed notebook Journal; real notebook
cover/subtitle and title remain. Required exact RGB/native back-path UI tests and
capture43 added, pending. A new isolated prominent full-width CTA strict audit
comparison investigates the unknown-element font finding without hiding it.
Full professional visual/usability acceptance remains unfinished, not certified.

## New structural increment and actual verification evidence

- Native whole-block Arrange screen, checked multi-block move, encrypted atomic
  save and stale/Unicode/draft preservation now implemented. Six new Apple tests,
  genuine native ciphertext→original web and actual screen/reopen gates added;
  pending, NOT claimed passed. Actual compiled Foundation source contracts PASS.
-94bbbc8 dedicated42-state page tour PASSED. Visually reviewed40-frame gallery
  excludes blank Quick Look25 and loading Photos39. Still not every page/state.
- Completed be42525592332 AND94 42525937610 native workflows FAIL overall;
  be actual normal/XXXL Dynamic Type reports an UNKNOWN unsupported-font element;
  actual XXXL server reachability also fails intermittently. Unmodified normal
  Form/SecureField and XXXL Form comparisons pass. No framework false positive
  established; no finding suppressed. Exact screenshots/logs inspected, fresh
  required audit evidence now exported before independent functional screen tests.
-1acd4dd actual Apple core/web/Go/Simulator build PASS; page/strict results verify
  separately. Its ENTIRE genuine native TLS/Go/Postgres + S3/source-image/
  backup-restore42527124183 SUCCESS. Simulator != signed iPhone delivery.
- Source review found original media DELETE returned204 after a failed sweep.
  Corrected to existing500/503 errors so clients retain retry intent. Actual Go
  full tests/vet plus complete/partial-sweep/retry/owner-object-boundary/error
  redaction tests PASS locally. New native strict empty204/ID/token/status tests
  and actual TLS/Go/Postgres orphan delete/chunk404/shared-media-preservation
  integration verify separately. No cipher/key/schema/auth change.
  Native permanent-purge confirmation/reference/recovery/outbox lifecycle UI
  remains missing; no destructive button/stub or secure-erasure claim.

## November 8, 2026, 4:49 PM EST verified core/live + actual page evidence

- be6189b AND94bbbc8 full Apple native core including EIGHT notebook fault,
  Unicode/CAS, empty/capacity, draft/media/restart and compatibility tests PASS;
  actual original-web decrypt/router, original Go verifier and genuine universal
  Simulator builds PASS. Entire genuine native TLS/Go/Postgres cascade/restore,
  shared encrypted media/retry and separate S3/source-image/backup-restore workflows
  42525592525 and42525937612 SUCCESS. No original crypto/protocol change.
- First dedicated real page tour produced28 actual same-build states, not all
  intended pages. Its Quick Look capture showed premature blank chrome; later
  actual AX evidence shows genuine decrypted text, but dismissal had not finished
  before an underlying Journal navigation attempt, so media outbox/recovery tour
  FAILED. Not a passing media screen certification. It now requires actual
  rendered text and real Done-button disappearance, and retains normal production
  animations for system media/pickers. No coordinate tap or ignored assertion.
  New page artifacts also export actual test summary JSON for early diagnostics.
- Current42-state tour and ALL strict production normal/XXXL audits remain
  required, not certified. Screenshots observed != all planned controls passing.

## November 8, 2026, 4:31 PM EST page coverage and recoverable notebook increment

- Current a7c9fdba Apple full core, exact Unicode/label and encrypted metadata
  fault/retry preservation tests, actual web decoder, Go verifier, Simulator
  app/package PASS (42523742373). Metadata, heading/formatting, original-font
  load/audit/license, move, deletion/restore, failed-writing and XXXL geometry
  screens PASS in that run. Overall native workflow FAIL: both normal and XXXL
  production onboarding Dynamic Type audits still report an unknown element.
  Earlier ae4 deletion/geometry failures were intermittent, not ignored; deletion
  now explicitly waits for real disappearance instead of an immediate query.
- A separate REQUIRED real Simulator page-tour stage now exports genuine page
  screenshots BEFORE independent functional/strict audit runs. Only the capture
  tour disables animations (DEBUG switch); the real UI states/controls/data are
  not mocked, and ALL normal/XXXL production audit findings remain failures.
  Target inventory includes Journal/search, Calendar, notebook create/edit/cover,
  move form/choices, rich block/run/expanded formatting, metadata, all appearance
  choices/dark settings, privacy/licenses, actual offline media/outbox/recovery.
  Screenshots and successful navigation must be observed before claiming coverage.
- New DEBUG-only public media fixture genuinely stages original encrypted chunks
  and durable outbox, then opens the production offline decrypted preview. It has
  no relay and claims no authentication/upload/server success. Production cached
  and queued previews no longer require an unused relay object; remote fetches
  still require original identity/auth/trusted TLS. Native crypto is unchanged.
- Notebook cascade freezes the reviewed DOWNLOADED original set; it commits one
  encrypted recovery plus notebook/entry tombstones atomically. Pending writing,
  rich drafts, encrypted cache/chunks and media queues are retained. Same-ID
  restoration requires every original tombstone unchanged, refuses remote edits,
  missing/new/duplicate records and overflow; checked limits fail without eviction.
  Byte-exact checkpoint comparison also refuses concurrent NFC/NFD-only changes.
  This is recoverable deletion, NOT secure erasure or an atomic server-wide fence.
  Unseen/concurrent remote additions remain an explicit original-protocol limit.
- Deleted-only media uploads pause and remain retained; shared live refs and a
  restored original reactivate uploading. Tombstones are publishable without
  waiting for a failed pending attachment. Actual Foundation source adversarial
  tests PASS; eight new Apple tests, original-web decrypt/router assertions and
  genuine TLS/Go/Postgres delete/restore/shared-media cases are added and pending.
- Full feature/visual parity and physical iPhone/installable release remain NOT
  complete. Professional cohesive design is acceptance, not current certification.
  The source protocol/keys/ciphertext and existing server behavior are unchanged.

## November 8, 2026, 4:09 PM EST verified screen/metadata checkpoint

- Completedc810 native42521928122: actual entry Delete → Settings encrypted
  original → Restore as new → rich reader/tasks PASS; actual Move → destination
  notebook with original content retained PASS; failed writing close/resume PASS.
  Covers/paper RGB, notebook metadata Save, rich/task/text editing, HTTP rejection,
  native Form controls and actual XXXL geometry also PASS. Overall workflow FAIL:
  production normal/XXXL strict audits and Formatting content Menu still fail.
  More's content Menu DID pass in this revision; native Buttons in the new
  increment still need their own actual tests. No coordinate tap workaround.
- Actuala0f2b1d Apple full core including FOUR new metadata tests, metadata
  ciphertext → actual original-web decoder, original Go verifier and genuine
  universal Simulator app build/package PASS in42522662183. New native metadata,
  formatting and all strict audits are still running; not overall native GREEN.
  Entire genuine native/TLS/Go/Postgres/S3/backup-restore42522662189 and ordinary
  CI42522662238 PASS. Fonts/remaining fixes have independent subsequent gates.
- Source review caught two genuine label-loss paths and fixed them: Swift's
  canonical String equality conflated distinct original-web NFC/NFD labels; and
  unrelated plain-writing saves split existing literal-comma labels. Byte-exact
  identity, per-row deletion and original metadata retention now preserve them.
  Existing plain writing shows labels read-only and directs to the real individual
  metadata form. Explicit new comma input matches original web normalization;
  unknown future label schemas fail closed, unchanged fields remain opaque.
  Explicit recovered text copies also retain unchanged original labels.
- Actual compiled-source Unicode/comma/unknown-schema regressions PASS locally,
  with byte-exact web goldens (not canonical-equality assertions). New real Apple
  encrypted metadata fault/old-byte preservation/reopen/retry/media-draft retention
  tests are added and pending at the newest source. No crypto, snapshot version,
  keys or wire formats changed; no full lifecycle/device readiness claim.

## November 8, 2026, 4:02 PM EST typography increment (iOS gate pending)

- Added SIX exact original-web Latin normal/italic variable fonts, losslessly
  decompressed to TrueType. All glyph maps/orders/font tables except only the
  checksum adjustment are asserted unchanged, and conversion is byte-reproducible.
  Complete original SIL OFL1.1 notices ship in the app and a local offline license
  viewer. Source/package/output/license SHA256s are enforced in browser CI.
- Actual unlocked journal/notebook titles, prose, plain/rich editor and code runs
  now select the original fonts: Modern sans headings/serif writing, Terminal
  sans headings/writing, other skins serif headings/writing, Spline mono code.
  Dynamic Type uses `Font.custom(relativeTo:)`; no global fixed UIFont override,
  no runtime font download or telemetry. Native navigation/controls adapt to iOS;
  missing/non-Latin glyphs use native fallback. This is NOT exact visual parity.
- Actual compiled Swift role selection and ALL29 browser checks + production
  typecheck/build PASS locally. Added actual six-face UIFont-load, bundled-license
  and strict Dynamic Type UI assertions. Real iOS results remain pending; source
  names and hashes alone do not prove UIKit loading/accessibility.
- Existing production strict audits remain blocking. Added a SEPARATE unmodified
  native SecureField strict comparison to isolate the remaining opaque finding;
  existing unmodified Form comparison and ALL production audits stay unchanged.

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
- Notebook cascade/shared-media purge remain outstanding. Deletion recovery is
  intentionally NOT secure erasure. Original font bundling is added below; actual
  iOS font-load/scaling gate remains required.

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
