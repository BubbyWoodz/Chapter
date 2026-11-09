#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
envfile=${CHAPTER_ENV_FILE:-$root/.env.chapter}
[[ -f "$envfile" ]] || { echo 'First run ./deploy/chapter/init.sh; see docs/CHAPTER-SERVER.md.' >&2; exit 1; }
export CHAPTER_SOURCE_DIR=$root
# Never mutates another compose project, env file, version file or volume.
exec docker compose --project-name "${CHAPTER_PROJECT:-chapter}" --project-directory "$root" --env-file "$envfile" -f "$root/deploy/chapter/compose.yml" "$@"
