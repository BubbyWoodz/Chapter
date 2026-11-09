#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
target=${CHAPTER_ENV_FILE:-$root/.env.chapter}
command -v openssl >/dev/null || { echo 'OpenSSL is required to generate local secrets.' >&2; exit 1; }
# Exclusive creation, never replaces an existing install or prints its secrets.
umask 077
set -o noclobber
{
  printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)"
  printf 'S3_SECRET_KEY=%s\n' "$(openssl rand -hex 24)"
  printf 'ADMIN_TOKEN=%s\n' "$(openssl rand -hex 32)"
  printf '%s\n' 'CHAPTER_VERSION=source' 'CHAPTER_BIND=127.0.0.1' 'CHAPTER_HTTPS_PORT=8443' 'SITE_ADDRESS=localhost' 'DEFAULT_SNI=localhost' 'REQUIRE_APPROVAL=true' 'QUOTA_BYTES_PER_OWNER=10737418240'
} > "$target"
printf 'Created private environment file: %s\nNo secrets were printed. Configure hostname/bind before LAN use.\n' "$target"
