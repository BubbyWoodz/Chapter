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
7. Reviewed browser at-rest migration, integrity/freshness protocol hardening,
   true per-device revocation, independent audit and release/image provenance.
8. Accessibility, physical LAN/Tailscale/cellular, TLS/permission/backup tests and
   signed beta. A pushed source tree is not an installed app or full parity.
