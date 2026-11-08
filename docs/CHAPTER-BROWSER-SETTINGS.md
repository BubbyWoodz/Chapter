# Browser settings durability and compatibility

This is an additive Chapter-client local persistence change, not an encryption redesign. Original `v:1` AI-settings ciphertext, keys, AAD and original relay record codec remain unchanged. Shared appearance is optional data inside that original encrypted record. No telemetry, extra remote endpoint, AI enablement or external content request is introduced.

## Behavior

- A production serialized journal owns loading, editing, remote receives and acknowledgements. A failed IndexedDB transaction does not update in-memory truth, consume the relay page, or silently clear the outbox. The storage promise resolves on transaction completion, not request success.
- Settings are owner-scoped. Existing global ciphertext is read and, after successful decrypt, migrated non-destructively. The legacy encrypted copy remains until an explicit rotation/deletion lifecycle verifies ownership and atomically compares the exact old ciphertext before removing it. Another owner's legacy bytes are not removed.
- IndexedDB compare-and-swap rejects a stale tab's write in the same transaction. Preferences offers explicit Reload; then review/retry the failed edit. This is not automatic multi-tab CRDT merging. A failed unsaved UI choice is not represented as a successfully saved recovery version.
- Same-ID/equal-clock authoritative server records win, while displaced dirty/equal-clock configurations are retained as separately encrypted recovery snapshots. Canonical IDs converge deterministically. Delayed acknowledgements cannot clear newer edits; pending tombstones survive offline restart.
- Restoring theme preserves current assistant credentials. Restoring assistant configuration preserves current theme and forces assistant disabled. The previous saved version is archived. Unknown settings fields are retained; unsupported settings versions fail closed. Recovery copies contain encrypted credentials, so removal/backup/retention deserves the same protection as the current record.
- Lock closes the journal and rejects queued publication; a write already committed may safely remain encrypted. Next unlock waits for previous work. Rotation rekeys the local checkpoint/recoveries using the existing derived key and original crypto; old ciphertext is retained if new persistence fails. Rotation's entire application lifecycle still needs real failure-injection acceptance, not just the passing checkpoint test.

## Compatibility boundaries / remaining work

Original web/server ciphertext is interoperable. **Local IndexedDB outbox/recovery metadata is Chapter-specific.** An older cached upstream client will not read the new scoped dirty outbox or recovered versions; do not downgrade a browser cache with pending work. Original upstream theme UI is local-only and will not apply synced appearance until updated to Chapter. This is not a wire protocol change or a promise that older local clients understand the new journal.

Recovery storage is bounded at 256 snapshots and fails closed at the cap rather than silently discarding a version. A complete explicit export/prune/retention UI is still needed before declaring recovery lifecycle finished. Storage quota failure is surfaced; private browsing/eviction/power loss is not preventable by this layer. Server reachability still is not authentication.

## Reproducible evidence

`pnpm --filter client check` includes `scripts/settings-journal.ts`, using the **actual production journal, original crypto and actual browser adapter** with test-only pinned fake-indexeddb. It tests request-success/transaction-abort rollback, serialized save/pull, stale acknowledgement, equal-clock conflict/restart/recovery, cross-tab CAS/reload, tombstone restart, lock races and checkpoint/recovery rekey with wrong-key/destination-conflict rejection. This is standards-based adapter fault simulation, not a real browser crash test.

`native-live-theme.ts` additionally sends the production journal's records through the genuine original Go relay/Postgres with trusted TLS and native URLSession; the updated verification requires a browser equal-clock divergence rejected by the real relay, authoritative convergence, encrypted recovery and restart. This extended check requires a green CI result; local scripted tests alone do not prove end-to-end operation.
