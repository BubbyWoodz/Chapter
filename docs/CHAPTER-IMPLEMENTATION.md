# Chapter implementation ledger

## Milestone 1: private native connectivity and durable writing foundation

Changes are on a feature branch, not main. User priority: preserve existing journals;
no custom cipher, no silent wire-format/key change, no risky web database migration.
The broader full-parity project is **still in progress** after this milestone.

### Safe upstream hardening

1. Reject web relay URLs containing embedded credentials/query/fragment while
   retaining existing HTTP(S), IPv4/IPv6 and deployment-prefix compatibility.
2. Relay request logs use matched route templates rather than record IDs, archive
   names, arbitrary unknown paths or query strings. JSON decode errors no longer
   echo attacker-controlled field names; internal failure diagnostics log error
   type rather than possible sensitive driver error text.
3. Remove owner identifiers and exact reminder schedules from the placeholder
   reminder dispatcher logs. Reverse proxy, DB and third-party logs are separate.
4. Add non-admin `GET /v1/info` with public protocol facts and limits; no secrets,
   owner counters, internal hostnames or unverified proxy-service claims.
5. Keep existing content keys, derivation labels, ciphertext version, AAD,
   signature domains, wire fields, relay storage and database schema **unchanged**.

### Native foundation

See [native README](../apps/ios/README.md) for precisely implemented and missing
features. Actual SwiftUI app + Xcode project, encrypted device-local snapshot,
real phrase/auth/E2EE sync, durable plain entry editing, native navigation/search/
calendar/notebooks, conflict recovery and explicit authenticated attachment preview.
No wrapper or pretend-success buttons. Missing features are listed in app settings.

### Why the existing browser database was NOT migrated in this patch

The current worker/VFS stores SQL columns and media/thumbnail BLOBs as plaintext.
Encrypting it safely requires a reviewed encrypted VFS or encrypted-record storage
redesign, key transfer into the worker, schema/migration design, interrupted-migration
recovery, search/media outbox handling and tests against historical OPFS fixtures.
A hurried column-level conversion risks silent data loss and is worse than an
honestly documented limitation. No existing browser/relay data is touched here.
The native store is new, separate, encrypted from first write and fail-closed.

### Checks actually run on the Linux box

- Baseline: `pnpm install --frozen-lockfile`, all original **23** client regression
  scripts; `go test ./...` from `server` passed before edits.
- After edits: web typecheck + Vite production build; full **25-script** regression suite with
  URL/privacy/native fixture additions; Go tests including new public-info and
  log-redaction regressions; `go vet ./...`; Swift syntax parsing; Xcode PBX project,
  Info.plist/privacy manifest lint and scheme XML parse; `git diff --check`.
- Swift syntax parsing is **not** typechecking or iOS execution. Actual native
  package tests, reverse Swift→web fixture leg and simulator app build are defined
  in `Native iOS` macOS CI; check that run's result before saying they passed.
- No live PostgreSQL/MinIO integration, browser media test, on-device test,
  accessibility audit, Tailscale setup or distribution signing was performed locally.

### Gate for continuing, not for declaring completion

1. Make native macOS CI green; fix all compile/interop findings before device use.
2. Run disposable reference server + web + physical iPhone: phrase, approval,
   notebook/entry CRUD, media chunks, offline kill/restart, concurrent edits,
   server-switch isolation and pending outbox. Capture traffic/storage/backups.
3. Native ProseMirror-compatible rich editor/renderer: every mark/node and unknown
   field preserved; cross-client save/edit golden documents; no plaintext fallback.
4. Complete protected media capture/upload, codec compatibility, templates and
   import/export; large-file/cancellation/disk-full/privacy tests.
5. Complete AI/interview/video-film/STT/maps only with explicit destination consent;
   no telemetry or mandatory cloud. Preserve operator policy.
6. Complete lifecycle (rotation/deletion/unlock), local reminders, appearance/12
   locales/RTL, search/calendar/stats/badges and separate operator tools.
7. Review original-protocol limitations honestly; do not redesign encryption or
   migrate browser storage under the current scope. Verify release/image provenance.
8. Accessibility, physical LAN/Tailscale/cellular, TLS/permission/backup tests and
   signed beta. A pushed source tree is not an installed app or full parity.


## Follow-up: verified native build foundation

Continuation remains on the same draft PR; no default-branch merge. Fixes include
portable digest extraction; checked JavaScript-safe clocks/cursors, date/media
numeric bounds; semantic rather than deterministic Ed25519 tests, independently
cross-verified in web and Go; actual native HTTP auth transcript regressions;
lost-ack, tombstone/equal-clock conflict retention; safe entry-only restoration.
The Xcode project now contains a Simulator UI test target with connection-screen
accessibility and Dynamic Type audits plus HTTPS-only fail-closed behavior. CI
uploads genuine xcresult/captures of public-fixture screens. These automated tests
are not physical-device VoiceOver, LAN/Tailscale, backup/key-loss or live-stack
interoperability certification. Refer to the PR checks for actual pass/fail status.


## Current scope and final deliverables (November 8, 2026 AST)

The latest direction is functional native parity with the original Mneme encryption
and behavior. Do not redesign encryption, change HKDF/AAD/signature domains, or
silently migrate keys/wire records. Earlier security-design possibilities are not
an instruction to implement them now. Preserve compatible, additive encrypted
mobile storage and already committed safe correctness fixes. Existing metadata,
freshness, revocation and plaintext-web-storage limitations remain disclosed;
passing functional tests is not a claim that those limitations disappeared.

The project is not finished at a source PR or Simulator build. Required deliverables:

1. Reproducible Chapter server/web Docker artifacts and a compose/install/upgrade
   runbook, with Chapter-owned local tags/artifacts rather than accidentally pulling
   or publishing `ghcr.io/mneme-blog/*`. Keep original database/media formats,
   volume ownership/names and `/mneme` compatibility deliberate; renaming a compose
   project can silently select empty volumes and must not be called migration.
2. Clean-stack startup/health/migration/backup-restore tests plus real native-client
   registration, sync, offline edits/conflicts and media integration. Existing
   crypto fixtures and URLProtocol tests alone do not establish that integration.
3. Full native feature parity with preserved rich document schema/media, followed
   by an actually installable signed iPhone build and documented server connection.
   Unsigned Simulator `.app`/Xcode source are not iPhone-installable distribution.
4. No deployment on anyone's devices/services, registry/release publication, signing
   credential acquisition, TestFlight upload or App Store submission is implied by
   preparing/testing artifacts. Those externally visible steps need the appropriate
   explicit authorization and signing route when the app is ready.

### Sanctioned eventual signing routes

Apple documents free Personal Team installation from Xcode on your own device;
provisioning expires after seven days and requires rebuilding/reinstalling. A
registered-device Development/Ad Hoc export or TestFlight distribution uses the
appropriate Apple Developer Program team/certificates/profiles. No Apple account,
certificate, private key, profile or App Store Connect access was obtained here.
An authorized Apple team/device distribution route is a future user-only dependency,
not an excuse to stop building/testing the app now. Do not upload private signing
material into this repository or CI artifacts.

Official sources read for this plan:
- https://developer.apple.com/help/account/basics/about-your-developer-account/
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases

Next implementation priority after a green native foundation: lossless native rich
viewing/editing and encrypted media capture/upload/download; retain unsupported
nodes/attrs/marks without flattening. Server packaging and live integration must
progress as real milestones alongside the remaining parity matrix, not be deferred
until calling a source-only client finished.

### Strict UI findings and corrections

Real Simulator captures identified a compact prominent button whose default layout
could not accommodate every Dynamic Type size. The connection action now wraps
its semantic headline in a full-width, minimum-44-point, vertically expanding
button; explanatory text and input rows are allowed their full natural height.
No maximum Dynamic Type cap, shrinking font, ignored audit issue or test exclusion
was introduced. The first strict UI run already passes HTTPS rejection; remaining
audit status is recorded in actual CI, not inferred from the source changes.

The natural-height custom button did **not** resolve the audit: actual 767f6c6
captures still reported partial Dynamic Type support on it and an unidentified
XXXL finding. The next diagnostic uses a standard Form action (no custom button
style), and applies XXXL through the Simulator's real OS preference rather than
a forced launch override. All original audits remain required, and the XXXL test
asserts the heading really grew. This is a hypothesis being tested, not a claim
that the remaining findings were false positives. Separate xcresults/captures
retain both sizes, with bounded test timeouts so failures cannot silently hang.

The real-OS test at d8e1bca **also failed** both Dynamic Type audits, while the
XXXL-size assertion, HTTPS rejection, native core/interop and universal app build
passed. Thus neither extra space/custom styling nor a launch-argument override
has been established as the cause. Do not call this resolved or dismiss the
findings as false positives. Next diagnostic logs Apple's compact/detailed issue
descriptions and adds a separate real-XXXL input/button geometry test with genuine
captures; the original strict audits still fail the workflow on every finding.
No rich-document/media feature implementation was started while this verification
gate remained unresolved. The correct next step is evidence-driven localization,
not repeated unverified styling edits or ignoring a category to make CI green.

## Independent rich-document vertical slice (verification in progress)

The onboarding audit remains required, but no longer blocks independent feature
implementation indefinitely. Native structured rendering and real individual
text-run/task editing now patch the original ProseMirror JSON, preserving every
unknown field/mark/node and existing media reference. Unsupported nodes remain
opaque; formulas show source and tables/custom cards have explicit fidelity limits.
No HTML/Markdown flattening, invented cipher or protocol change was introduced.

Rich run drafts autosave inside the encrypted local snapshot, survive lock through
Settings, and refuse stale/deleted-record application. Local payload v2 prevents
older preview binaries silently dropping drafts; current code reads v1 without
rewriting/rekeying and upgrades only on the next atomic save. Unsupported versions
fail closed. This local migration does not touch upstream browser/relay formats.

Local actual Foundation-source harness, web build and all 25 regressions pass.
Eight new native tests, Apple→web encrypted rich golden checks and a genuine app
UI edit/task smoke test are added; their actual Apple CI result must be checked
before calling this slice verified on iOS. The Debug public encrypted fixture is
isolated and has no real identity/relay; it is not production authentication proof.
Encrypted media upload/capture and a full structural editor remain next, not done.
See [the exact per-feature remaining matrix](CHAPTER-FEATURE-STATUS.md).

Actual first rich-slice Apple run 42450050069 has passed 28 native tests, the
independent web rich-ciphertext/tree/media-reference checks, Go signatures and
the real universal Simulator app build; its UI tests are still being evaluated.
A follow-up adds exact ECMAScript Unicode-whitespace cases (BOM versus NEL),
checks Debug fixture drift and gives task controls a minimum 44-point hit target.
Those follow-up changes still require their own Apple CI; local actual-source
Foundation tests pass. Do not infer a whole-workflow pass from successful steps.

Retained audit diagnostic run 42449468564 still failed strict Dynamic Type despite
its independent actual-XXXL geometry test passing (input 87 points, action about
163 points). Apple detailedDescription supplies no unsupported-category list.
This remains an unresolved release gate, not a reason to remove the audit or stop
independent functional work. New rich UI fixture captures are not device-auth proof.

The first rich UI smoke test failed before opening the fixture, not during an
edit: its exported hierarchy remained the connection form. The handcrafted
Debug configuration omitted SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG, so the
Debug-only public fixture code was compiled out. The follow-up explicitly defines
DEBUG for Debug only; Release retains no fixture path. This fix is being verified
in the next Apple run. No successful rich edit screenshot or device test is
claimed from that failed smoke run. The production renderer/core did compile.
