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
| Native rich viewing | Styled inline marks, headings, paragraphs, lists/tasks, quotes/code, approximate tables, source math, simplified media/location/interview cards | New web-generated golden document and actual Foundation logic tests. Actual Apple compile/UI results pending this slice; unknown nodes kept opaque |
| Rich editing | Existing text-run editing and task checked state only; patch original JSON | New tests assert full tree/unknown attrs/marks/media IDs retained, stale writes rejected, Unicode/empty-run behavior. No full selection-based rich editor, structural/formatting toolbar, title/date/label controls for rich records or full custom-node editor |
| Rich local drafts | Encrypted autosaved run drafts; resume in Settings; explicit apply rejects changed/deleted record | New native migration/encrypted recovery tests and real Debug fixture UI edit test added; device failure/restart/disk-full acceptance not complete |
| Rich cross-client sync | Same encrypted record protocol after patch, regenerate bodyText with actual web docToText semantics | Native-produced edited ciphertext must open in actual web decoder with entire expected tree/media IDs. Defined in macOS CI; not a live server/browser round trip |
| Entry links/Markdown/math | Stored link labels and LaTeX source retained; external web/mail links require explicit confirmation | Backlink/navigation UI, Markdown/source editing and exact native math typesetting missing; no silent external fetches |
| Media download | Existing explicit authenticated chunk download, Quick Look, protected temporary plaintext | Native/web media crypto checks; 128 MiB cap, OS codec limits; real-stack/device playback and cleanup not certified |
| Media authoring/offline | NOT implemented | Capture/picker/import, encrypted upload outbox/retry, encrypted durable cache, large-file/codec parity next |
| Templates/interview types | Opaque sync/preservation only | Native management/application UI missing |
| AI/Q&A/guided/freeform interviews | NOT implemented | Native configuration, explicit destination consent and operator-policy behavior missing |
| Audio/transcription/video/films | Read-only simplified cards/transcripts + existing attachment preview | Recording, per-question capture, STT, film rendering/editor all missing |
| Locations/maps | Read-only place names and explicit encrypted attachment previews | Native insertion/editing/snapshot flows and explicit network consent missing |
| Import/export/backups | NOT implemented natively | Day One, journal exports/import, recovery/restore and operator backup UI missing |
| Appearance/language | System-native layout and Dynamic Type | Strict onboarding audits currently fail; exact theme/12 locales/RTL parity, whole-app VoiceOver/device audits missing |
| Reminders/lifecycle | Background lock only | Reminders, phrase creation/rotation, vault/journal deletion, WebAuthn/PRF and operator administration/update UI missing |
| Sync reliability | Manual sync, encrypted pending records, first 100 pushes per pass, recoverable entry conflicts | Core adversarial ack/clock/conflict tests passed; automatic retry, pagination/drain, background/lifecycle and real two-client concurrency tests missing |
| Local storage | Device-only user-presence Keychain + AES-GCM snapshot; protected/excluded from backup | Version 1→2 read migration preserves keys and old file until next save; older previews reject v2 instead of dropping drafts. Actual hardware Keychain/backup extraction not certified |
| Server distribution | Existing upstream-compatible Go/web source/Dockerfiles only | Chapter-owned artifacts/installer/upgrade/backup-restore/clean-stack integration still required; upstream image/updater defaults must not be used accidentally |
| iPhone distribution | Xcode source and unsigned Simulator artifacts only | No signed device IPA, TestFlight or physical-device certification. Apple signing route later, not obtained here |

## New test files

- `apps/ios/ChapterCore/Tests/ChapterCoreTests/RichDocumentTests.swift`:
  seven native tests for web-preview parity, tree preservation, task/text patching,
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
