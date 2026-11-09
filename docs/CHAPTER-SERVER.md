# Chapter server: source-build install and verification preview

This separate **new-install** profile builds Chapter-owned server/web/object-store
images. It does not change the original Mneme crypto, records, database migrations,
backup format or `/mneme` URL prefix. The web UI still contains upstream branding;
this is not a full-parity release. No deployment/public registry publication occurs
when a PR builds this profile. Read the exact CI outcome before using artifacts.

## Build a clean installation

Requirements: Docker Engine with Compose v2, OpenSSL, enough disk/RAM to compile Go
and the object store. Run from the exact Chapter source revision:

```
./deploy/chapter/init.sh
# Edit .env.chapter locally; never post its secrets into chat or commit it.
./deploy/chapter/chapter.sh build
./deploy/chapter/chapter.sh up -d --no-build --wait --wait-timeout 180
```

`init.sh` exclusively creates a mode-0600 environment file with random hex database,
S3 and admin secrets. It refuses to overwrite an existing file. The default compose
project is `chapter`: distinct volumes, no automatic discovery/adoption of a previous
Mneme deployment, no destructive volume cleanup or privileged host updater. PostgreSQL
and object storage are not published on host ports. Update checking/apply are off;
approval is on and the default per-owner storage limit is 10 GiB.

The initial bind is **127.0.0.1:8443**, not a public deployment. For a phone, configure
`CHAPTER_BIND` to a deliberate reachable LAN/tailnet interface (or consciously
`0.0.0.0` plus firewall), and `SITE_ADDRESS` / `DEFAULT_SNI` to the matching server
hostname. Use `https://<server-host>:8443/mneme` in the native client. `localhost` on
the iPhone means the phone, not your server. Tailscale supplies a route, not login.

Caddy uses its internal CA. Export ONLY its public root certificate:

```
./deploy/chapter/chapter.sh cp web:/data/caddy/pki/authorities/local/root.crt ./chapter-root.crt
```

Trust that certificate through your device's normal certificate-management UI, or
configure a reviewed trusted-HTTPS reverse proxy/certificate setup. Never turn off
native certificate checks or use an ATS global bypass. Keep the CA private key in
its persistent TLS volume. This preview does not automate phone certificate setup.
Operator approval uses the existing `/mneme/admin` interface and the locally held
admin token; no admin credential belongs in the consumer app binary.

## Install a tested CI image bundle

If the **Chapter installable server and native live relay** workflow's packaging job
passes, download its `Chapter-server-linux-amd64` artifact (seven-day CI retention):

```
sha256sum -c SHA256SUMS
mkdir chapter-source && tar -xzf Chapter-server-source.tar.gz -C chapter-source
docker load -i Chapter-server-linux-amd64-images.tar.gz
cd chapter-source
./deploy/chapter/init.sh
# Configure .env.chapter; set CHAPTER_VERSION to the SOURCE_COMMIT in the artifact.
./deploy/chapter/chapter.sh up -d --no-build --wait --wait-timeout 180
```

The bundle contains own-named images and PostgreSQL, exact source/license/build
instructions, source revision, image IDs/registry digests and checksums; no runtime
volumes, credentials, real journals or test backups are exported. Initial CI artifact
architecture is **Linux amd64**. ARM source builds and other hosts need their own
verification. Base Docker tags are version-family tags, not a hermetic digest lock:
image IDs in the bundle pin the actual tested output. Rebuilding later can receive
base-image security updates and is not promised bit-for-bit identical. Checksum is
integrity information, not a signed release/security audit.

MinIO's historical Docker images are no longer a reliable install dependency. This
profile builds the official source release `RELEASE.2025-10-15T17-29-55Z` using its
published `go install` route, which includes the upstream service-account policy
security fix. Source: https://github.com/minio/minio/releases/tag/RELEASE.2025-10-15T17-29-55Z
MinIO is AGPL software too; preserve its corresponding-source/license obligations.

## Backup, restore and safe upgrades

The original opaque-ciphertext backup format is retained. It includes metadata and
all vaults/media but **no recovery phrases or decryption keys**. Copies still expose
metadata and permit offline guessing of weak/lost credentials; retain appropriately.

```
./deploy/chapter/chapter.sh exec -T server /journald backup --out /backups/manual.tar.gz
./deploy/chapter/chapter.sh cp server:/backups/manual.tar.gz ./manual.tar.gz
```

Copy backups off the machine and keep the recovery phrase separately. Device-only,
unsynced iOS work is NOT in the server backup. Do not uninstall/downgrade or change
server namespaces before all pending work is safely synced or explicitly exported.

For a Mneme→Chapter migration, **leave the original running and volumes untouched**.
Export a verified original server backup, start an independent empty Chapter stack,
stop its web/server writers, and restore into that empty target with the original
CLI's typed confirmation. Example (operator must choose the correct empty project):

```
CHAPTER_PROJECT=chapter-new ./deploy/chapter/chapter.sh stop web server
CHAPTER_PROJECT=chapter-new ./deploy/chapter/chapter.sh run --rm --no-deps -v /absolute/manual.tar.gz:/fixture/archive.tar.gz:ro server restore /fixture/archive.tar.gz
CHAPTER_PROJECT=chapter-new ./deploy/chapter/chapter.sh up -d --no-build --wait
```

RESTORE REPLACES TARGET DATA. Never point it at the old/live project or blindly reuse
old PostgreSQL/MinIO volumes. Verify counts, decrypt real entries/media with the
existing phrase and all clients, and keep the original/backup until acceptance.
A changed browser origin has separate local storage, and the native app isolates
server URLs: offline/unsynced original client work must be dealt with first.

For subsequent upgrades: backup first; record old source revision, image IDs, env
and volumes; build/load the new uniquely versioned images; review migration/rollback
manifest (`/journald schema-info`); test on a restored independent copy before
replacing an active stack. Do not downgrade database or object-store formats blindly.
This first packaging gate proves same-format fixture restore, not every historical
Mneme release, filesystem, migration, downgrade or disaster-recovery scenario.

Optional transcription: `./deploy/chapter/chapter.sh --profile speech up -d` enables
Speaches. No models download by default; explicitly install the configured model
through the existing UI, understanding host/model repository egress. Native STT and
AI feature parity remain outstanding. Other external features retain original opt-in
behavior; no telemetry/cloud identity was added.

## Exact test boundaries

- Packaging CI builds actual images, boots fresh PostgreSQL + real S3 + Caddy + Go,
  trusts the public test CA (never disables TLS), then runs actual web auth/crypto,
  encrypted record and multi-chunk media round trips. It backs up and restores to a
  **different empty** stack and verifies decryption again before exporting artifacts.
- A separate macOS job starts isolated PostgreSQL + actual Go API/router/migrations
  and in-memory fixture media on loopback TLS. Production native URLSession performs
  auth, 205-record batched pushes/paginated pulls, pending-media reference gating,
  media upload/lost-ack recovery/download; actual web decoder checks server-returned
  native ciphertext. This does NOT substitute the real S3 container test or certify
  the full native app's UI/controller on a phone.
- Original required UI accessibility audits remain failing release blockers until
  independently fixed. A simulator build is not an iPhone-installable signed app.
