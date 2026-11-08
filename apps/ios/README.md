# Chapter native iOS — implementation milestones

A genuine SwiftUI iPhone/iPad application and Xcode project, **not a WebView or
Tauri wrapper**. This is an early, reviewable implementation, **not feature parity,
a released/installed app, or a security certification**. Do not use irreplaceable
journals until native build, disposable-vault integration and physical-device
security tests pass.

## Build

- macOS + Xcode 16 or later; iOS/iPadOS 17 deployment target.
- Open `apps/ios/Chapter.xcodeproj`, select scheme **Chapter** and a simulator.
- For a physical phone, choose your own signing team and unique bundle identifier
  in Xcode; no signing secrets belong in this repository.
- The local Swift package pins `jedisct1/swift-sodium` to commit
  `cfd195c76882aa9b997560ca7cb95d72fbf5db00` (0.11.0), including its bundled libsodium
  binary. Review its license/build provenance before distribution. BIP39 English
  wordlist comes from the existing `@scure/bip39` dependency; MIT notice is bundled.
- No analytics, remote-crash SDK, mandatory cloud account or iCloud capability.

```sh
swift test --package-path apps/ios/ChapterCore
xcodebuild -project apps/ios/Chapter.xcodeproj -scheme Chapter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

`.github/workflows/ios.yml` runs package tests, validates Swift-written ciphertext
with the real web decoder, and builds the **actual application** for the simulator.
A Linux `swiftc -frontend -parse` check is syntax only, not an iOS build.

## Real implemented vertical slice (device validation outstanding)

- Native tab/navigation/form UI, adaptive system styling, semantic text sizes,
  labeled system controls and native search. Accessibility audits remain pending.
- User-entered **HTTPS** server base URL (including port/path prefix); direct
  URLSession, local-network privacy declaration, LAN/Tailscale routing. No VPN
  management. No HTTP exception, certificate bypass, credentials in URL or redirects.
- Validate English 12-word BIP39 checksum; CommonCrypto PBKDF2-HMAC-SHA512,
  CryptoKit HKDF/Ed25519/X25519 and libsodium XChaCha20-Poly1305 exactly matching
  the web protocol. Phrase and bearer sessions are memory-only.
- Actual owner-authorized registration and Ed25519 challenge/verify auth;
  pending approval returns an explicit HTTP 403 status. No password/token imitation.
- Pull/decrypt every opaque record kind while retaining unknown JSON fields;
  browse existing entries/notebooks, local substring search, day calendar and
  entry/day counts. No server plaintext search/index.
- Create notebooks, create/edit native plain-text entries with dates/labels,
  confirmation-gated entry deletion, encrypted durable outbox and real push/pull.
- Plain-entry changes save immediately. Rich documents now have native structured
  viewing, individual formatted-run editing and task toggles. Edits patch the
  original JSON; unknown nodes/attrs/marks are retained, not round-tripped through
  plain text/HTML. Rich run drafts save encrypted on every change, resume from
  Settings after locking, and apply explicitly with stale-document rejection.
  The strict canonical guard still prevents using the plain editor on rich data.
- Recover losing unsynced edits when a newer remote record wins. Restore creates
  a separate entry. Equal-clock rejected writes remain pending (not falsely saved
  remotely). Acknowledgments never clear edits made while a request was in flight.
- Explicit lazy attachment previews: collect every media-bearing node type used
  by web exports (single/gallery/map/interview/legacy attachments); authenticate,
  fetch chunks, verify per-chunk AAD, decrypt to a protected temporary local file,
  then use native Quick Look. 128 MiB preview limit; unsupported codecs (including
  some WebM) report failure rather than deleting content. File/photo import and durable encrypted upload are now implemented below; camera/audio/video capture is not.
- Native snapshot is AES-256-GCM encrypted under an independent random,
  non-synchronizing, passcode-bound device-only Keychain key with user presence.
  Namespace includes server AND owner. Atomic encrypted replacement commits
  records/outbox/conflicts/cursor together. Authentication/load failure **does not
  regenerate keys or overwrite existing snapshots**.
- iOS complete file protection + backup-exclusion request; background lock,
  app-switcher privacy cover and clearing in-memory references. Playback files
  are temporary plaintext under complete file protection, deleted on lock/failure
  and cleaned after process restart. Separate durable media-cache files contain only original-protocol ciphertext.

## Server compatibility

Target the reviewed Mneme main commit
`36c5e61d8bb9af30664bc275823a397fc86d606a` or Chapter branch based on it;
Mneme v0.5.1 has the same auth/sync framing. Older unauthorised-registration servers
are not supported; no downgrade fallback. Prefix example:
`https://chapter.example-tailnet.ts.net/mneme`. Server health and service port must
be reachable; LAN/Tailscale reachability never replaces vault authentication.

Keep `mneme:*` AAD/signature domains and `journal-v1` HKDF salt stable: **renaming
these would orphan existing data**. The native AES-GCM snapshot is device-local
only; it does not change XChaCha wire records or migrate web OPFS/relay databases.

A public `GET /v1/info` is added to the Go relay with protocol facts/limits only.
It does not claim Caddy-only transcription is present, expose owner stats, or
replace authentication. The initial client uses the pinned protocol directly;
full version negotiation and service discovery remain future work.

## Known boundaries — full project remains in progress

Not yet implemented: full rich structural/formatting editor, exact math/custom-node/
merged-table rendering, Markdown/backlink navigation,
camera/audio/video capture and media above 128 MiB, templates/interview-type management,
AI Q&A/writing/interviews, video interviews/film rendering, transcription,
Day One import/journal export, interactive location insertion, theme/locale/RTL
parity, badges/streak/heatmap parity, reminder UI/scheduling, phrase generation
and rotation, WebAuthn/PRF unlock, vault/journal lifecycle controls and operator
administration/backups/update UI. Background sync, retry scheduling and detailed
network diagnostics also remain. Rich viewing renders marks, headings, lists/tasks, quotes/code and approximate
tables/cards natively. Math shows LaTeX source, unsupported nodes are labeled and
kept intact, and attachments remain explicit previews. This is NOT full fidelity.

No promise of full-feature reliability, background 30-second sync, stolen-device
immunity, server rollback protection or App Store readiness. No Apple credentials,
TestFlight upload, App Store submission or deployment was performed.

## Recovery and privacy tradeoffs

- **Keep the recovery phrase separately.** It is never persisted by this preview.
  A local key alone is not a replacement for the phrase.
- A passcode reset/removal, device loss or uninstall may make local encrypted data
  inaccessible. Synced data can be recovered with phrase + server; unsynced data
  cannot. Do not change devices until pending changes are synced.
- Backup exclusion is a system request, not a cryptographic guarantee. Durable
  snapshot ciphertext is protected by a device-only key that is not iCloud-synced.
- Lock closes views/drops references; Swift/OS memory erasure and OS Quick Look
  internals are not guaranteed. Test snapshots, locked-device files, cancellation,
  crash cleanup and backup extraction on physical devices.
- The server still sees IDs, counts, sizes, edit clocks and IP/timing. Inherited
  wall-clock LWW, unauthenticated deleted/clock metadata and no freshness proof
  remain. A single derived device identity still prevents per-phone revocation.
- No AI/maps/STT network calls exist in this preview. Synced AI settings are merely
  retained encrypted locally, not acted upon. Future optional services require
  explicit destination-specific consent on this device and matching server policy.
- Preserve AGPL notices/source obligations. Resolve distribution/license terms,
  crypto export questions and third-party notices before an App Store release.

## Build/privacy foundation follow-up

- Fixed portable SHA-256 digest-byte extraction. Protocol clocks/cursors are checked
  as nonnegative JavaScript-safe integers; clock advancement fails closed instead
  of wrapping/saturating. Invalid/nonfinite dates have a safe display fallback
  without changing stored JSON. Fractional/overflowing media sizes are rejected.
- CryptoKit may hedge Ed25519 signatures. Tests verify message/key/signature
  semantics, not deterministic byte equality; native-produced signatures are also
  verified independently by the real web library and Go relay domain builders.
- Native HTTP transcript tests exercise prefix routing, actual signed challenge
  exchange, future response fields, pending/wrong-owner/malformed inputs and token
  header safety through an isolated URLProtocol. This is not a live server test.
- Lost acknowledgment reconciliation, equal-clock collisions and tombstone intent
  retain recoverable versions. Metadata conflicts cannot masquerade as restored
  entries or overwrite notebook/settings singleton identities.
- The actual Simulator UI target tests initial connection/accessibility, largest
  Dynamic Type and HTTP rejection; CI preserves xcresult and fixture-only captures.
  See the PR checks for execution results; committed tests are not a pass claim.

## Test status and next milestone

See `docs/CHAPTER-IMPLEMENTATION.md` and the PR checks for exact execution status.
Tests committed here cover web↔Swift crypto fixtures, BIP39/auth signatures,
wrong key/id/nonce framing/tampering, encrypted snapshot recovery/fail-closed
behavior, server isolation, unknown fields, outbox acknowledgments, conflict copies
and all media-bearing document nodes. Tests are not a substitute for a live stack
or physical iOS device.

## Local snapshot version 3: encrypted rich drafts and media outbox

The local-only payload now uses version 3 so older preview binaries reject it
instead of silently dropping new draft fields. Current code reads versions 1 and 2,
upgrades only in memory, and writes version 3 on the next successful atomic save.
There is no rekey, AAD/cipher change, browser migration or server wire change.
Unsupported/corrupt versions still fail closed. Do not downgrade a native preview
while it holds unsynced entries or drafts. Recover pending edits before uninstalling;
the recovery phrase cannot recover unsynced device-only data after its key is lost.

A Debug-only `--chapter-rich-fixture` launches public sample content in an isolated
temporary encrypted store under an intentionally public fixture key. It has no
relay/identity and cannot unlock a real vault. UI smoke tests use this to exercise
actual rendering, encrypted task/run writes and draft save—not to claim production
Keychain or real-server integration was tested. This mode is absent from Release.

See [per-feature test status](../../docs/CHAPTER-FEATURE-STATUS.md).

## Encrypted media import/upload/offline preview (partial media parity)

Files and selected Photos images can be attached to an existing valid rich or
plain document, up to 128 MiB. The document tree and metadata are patched, never
flattened. File imports use security-scoped access; selected Photos content uses a
bounded protected transient file. A selected system provider may fetch from iCloud
or another configured provider at the user's request; Chapter adds no analytics,
automatic external-content loading, or cloud upload destination.

- Prepare original XChaCha media chunks (1 MiB plaintext, 41-byte overhead) in a
  protected, backup-excluded, server/owner-namespaced ciphertext directory.
- Atomic local snapshot v3 commits outbox and reference together after all chunks
  exist. Manual Sync uploads immutable ciphertext before sending referencing
  entries. A failed upload is retained; unrelated entries may still sync.
- PUT binary chunks, then POST complete with CIPHERTEXT byte total. Recovery after
  a lost complete acknowledgment GETs finalized metadata and compares every remote
  chunk to the queued bytes before clearing the queue. No regeneration/re-encrypt
  on retry. Corruption/missing chunks fail closed, not as a successful save/sync.
- Cache originals encrypted for offline previews; decryption uses protected
  temporary Quick Look files, cleaned on dismissal/lock/startup. Import cancels on
  lock; queued ciphertext is never treated as purgeable cache.
- Never downgrade a device with pending work: older v1/v2 previews reject v3.
  New readers migrate v1/v2 in memory, without rekeying or overwriting on read.

NOT certified: actual iPhone picker/provider interruptions, locked-file/backup
extraction, OS-private Quick Look copies, disk-full/power-loss durability, codec
matrix or a real phone→server→browser media round trip. Core/macOS and real relay
CI results are recorded in the feature ledger; passing a transcript test is not
physical-device acceptance. No cache quota/eviction/repair UI or orphan ciphertext
sweep yet. Camera/microphone/video recording, film editing and large-media parity
remain outstanding. Losing a device/Keychain can lose unsynced backup-excluded work.


### Native authoring preview / local format v4

Run formatting and new paragraph/heading/quote/list/task/code blocks now have encrypted resumable drafts. Original opaque nodes/marks/media are retained, and stale drafts refuse Apply. This is not yet a selection-based full ProseMirror editor. Local snapshot v4 preserves new formatting/new-block draft fields; v1–v3 read without rekey/rewrite and upgrade on next save. Old previews reject v4; never downgrade/uninstall with pending data. Original Mneme wire encryption is unchanged. Apple migration/reverse-codec/UI gates must pass for the new increment; see the feature ledger for exact verification state.
