#!/usr/bin/env bash
# Ephemeral macOS CI only. Production URLSession trusts a disposable public CA,
# not a trust-all delegate or disabled certificate verification.
set -euo pipefail
: "${RUNNER_TEMP:?CI only}"
# This workflow changes trust only inside a disposable hosted VM, never a
# self-hosted runner/user Mac. GitHub decommissions this VM when the job ends.
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS ]] || { echo 'Disposable GitHub-hosted macOS runner required' >&2; exit 1; }
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
pg=$(brew --prefix postgresql@17)/bin
work=$(mktemp -d "$RUNNER_TEMP/chapter-live.XXXXXX")
relay_pid=
cleanup() {
  local status=$?
  trap - EXIT
  echo "LIVE cleanup: terminate owned fixture relay"
  if [[ -n "$relay_pid" ]]; then kill "$relay_pid" 2>/dev/null || true; fi
  # Stop our disposable database BEFORE waiting for relay pool teardown. Never
  # wait forever for a child that retains a database/keepalive resource. This is
  # test-harness cleanup, not a claim about production graceful shutdown.
  echo "LIVE cleanup: stop isolated PostgreSQL"
  "$pg/pg_ctl" -D "$work/db" -m fast -t 10 -w stop >/dev/null 2>&1 || status=1
  if [[ -n "$relay_pid" ]]; then
    kill -KILL "$relay_pid" 2>/dev/null || true
    wait "$relay_pid" 2>/dev/null || true
  fi
  echo "LIVE cleanup: delete exact disposable public CA certificate"
  if [[ -f "$work/root.pem" ]]; then
    # remove-trusted-cert opens a headless authorization prompt on hosted macOS:
    # https://github.com/actions/runner-images/issues/12116 . Use the documented
    # exact-certificate delete, never authorizationdb changes or a wildcard.
    # Any remaining per-cert trust metadata dies with this disposable VM.
    # Failure remains a job failure; certificate verification is never disabled.
    python3 - "$work/root.pem" <<'PYCA' || status=1
import hashlib,re,ssl,subprocess,sys
try:
    with open(sys.argv[1]) as f: der=ssl.PEM_cert_to_DER_cert(f.read())
    # SHA-1 is the platform's certificate locator, NOT a protocol/crypto choice.
    fingerprint=hashlib.sha1(der).hexdigest().upper()
    subprocess.run(['sudo','-n','security','delete-certificate','-Z',fingerprint,'/Library/Keychains/System.keychain'], check=True, timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    anchors=subprocess.run(['security','find-certificate','-a','-p','/Library/Keychains/System.keychain'], check=True, timeout=15, capture_output=True,text=True).stdout
    for pem in re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',anchors,re.S):
        if hashlib.sha1(ssl.PEM_cert_to_DER_cert(pem)).hexdigest().upper()==fingerprint:
            raise RuntimeError('Fixture certificate still installed')
except (subprocess.SubprocessError, OSError, ValueError, RuntimeError):
    print('FAIL: disposable CA trust cleanup failed or exceeded 15 seconds',file=sys.stderr)
    sys.exit(1)
PYCA
  fi
  echo "LIVE cleanup: complete (status $status)"
  exit "$status"
}
trap cleanup EXIT
echo "LIVE phase: initializing disposable PostgreSQL"
"$pg/initdb" -D "$work/db" -A trust --encoding=UTF8 --no-locale >/dev/null
"$pg/pg_ctl" -D "$work/db" -l "$work/postgres.log" -o "-h 127.0.0.1 -p 55432 -k $work" -w start >/dev/null
"$pg/createdb" -h 127.0.0.1 -p 55432 chapter_native_test
export TEST_DATABASE_URL="postgres://$(whoami)@127.0.0.1:55432/chapter_native_test?sslmode=disable"
export CHAPTER_NATIVE_FIXTURE=1 CHAPTER_FIXTURE_DIR=$work
echo "LIVE phase: compiling actual Go relay and fixture guards"
(cd "$root/server" && go test -tags integrationfixture ./e2e/nativefixture && go build -tags integrationfixture -o "$work/relay" ./e2e/nativefixture)
echo "LIVE phase: starting loopback TLS relay"
"$work/relay" > "$work/relay.log" 2>&1 & relay_pid=$!
# Bounded readiness check; no credentials appear in output.
for attempt in {1..60}; do
  [[ -f "$work/ready" ]] && break
  kill -0 "$relay_pid" 2>/dev/null || { echo 'Fixture relay failed before readiness'; exit 1; }
  python3 -c 'import time; time.sleep(1)'
done
[[ -f "$work/ready" ]] || { echo 'Fixture relay did not become ready'; exit 1; }
echo "LIVE phase: trusting ephemeral public CA in disposable runner"
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$work/root.pem"
export CHAPTER_NATIVE_LIVE_URL=https://localhost:55443
echo "LIVE phase: native URLSession integration test"
swift test --package-path "$root/apps/ios/ChapterCore" --filter LiveRelayTests
echo "LIVE phase: actual web reverse decoder"
pnpm --filter client exec tsx scripts/native-live-verify.ts
echo "LIVE phase: actual web → native → web appearance with normal CA validation"
NODE_EXTRA_CA_CERTS="$work/root.pem" pnpm --filter client exec tsx scripts/native-live-theme.ts --seed
swift test --package-path "$root/apps/ios/ChapterCore" --filter LiveThemeTests
NODE_EXTRA_CA_CERTS="$work/root.pem" pnpm --filter client exec tsx scripts/native-live-theme.ts --verify
echo "LIVE phase: complete"
