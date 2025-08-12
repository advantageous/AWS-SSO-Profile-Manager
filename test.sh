#!/usr/bin/env bash
set -euo pipefail

TOOL="./aws-sso-profile"   # adjust if needed

pass() { printf "✅ %s\n" "$*"; }
fail() { printf "❌ %s\n" "$*"; exit 1; }
note() { printf "—  %s\n" "$*"; }

# Create temp sandbox
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/sso-tool-test.XXXXXX")"
SESS_STORE="$SANDBOX/sessions.yaml"
AWS_CFG="$SANDBOX/aws-config"

# Keep sandbox if requested
if [[ -n "${TEST_KEEP:-}" ]]; then
  echo "TEST_KEEP=1 — keeping sandbox at: $SANDBOX" >&2
else
  trap 'rm -rf "$SANDBOX"' EXIT
fi

if [[ -n "${TEST_VERBOSE:-}" ]]; then
  echo "Sandbox: $SANDBOX" >&2
fi

GOOD_IMPORT="$SANDBOX/good-import.yaml"
BAD_IMPORT="$SANDBOX/bad-import.yaml"

# Seed files
cat >"$GOOD_IMPORT" <<'YAML'
OtherCompany:
  prefix: ev
  start_url: https://d-1067f984aa.awsapps.com/start
  sso_region: us-east-1
Advantageous:
  prefix: adv
  start_url: https://advantageous.awsapps.com/start
  sso_region: eu-central-1
YAML

cat >"$BAD_IMPORT" <<'YAML'
BrokenCo:
  prefix: bc
  # start_url missing on purpose
  sso_region: us-west-2
YAML

: >"$SESS_STORE"   # empty sessions store
: >"$AWS_CFG"      # empty aws config

# Run a command, capture rc; in verbose, print output to stderr
run() {
  local name="$1"; shift
  set +e
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  set -e
  if [[ -n "${TEST_VERBOSE:-}" ]]; then
    printf '%s\n' "$out" | sed 's/^/  | /' >&2
  fi
  echo "$rc"
}

expect_rc() {
  local want="$1"; shift
  local name="$1"; shift
  local rc
  rc="$(run "$name" "$@")"
  if [[ "$rc" -eq "$want" ]]; then
    pass "$name (rc=$rc)"
  else
    echo "Command:"; printf '  %q ' "$@"; echo
    fail "$name expected rc=$want but got rc=$rc"
  fi
}

# =====================
# Tests
# =====================

echo "### Test 1: configure --import-file (all sessions) dry-run ok"
expect_rc 0 "configure-import-all-dry-run" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive --force

echo "### Test 2: configure conflict without --force in non-interactive -> error"
# First, actually write once (no dry-run) so conflicts exist
"$TOOL" configure --config-file "$SESS_STORE" --import-file "$GOOD_IMPORT" --non-interactive --force >/dev/null
expect_rc 1 "configure-conflict-no-force" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive

echo "### Test 3: configure conflict with --force in non-interactive -> ok"
expect_rc 0 "configure-conflict-force" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive --force

echo "### Test 4: configure fail on missing fields (no prompts, any mode)"
expect_rc 1 "configure-missing-fields" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$BAD_IMPORT" \
  --dry-run --non-interactive

echo "### Test 5: list from --import-file"
expect_rc 0 "list-keys" \
  "$TOOL" list \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run

echo "### Test 6: generate for one key from --import-file (no existing block) ok"
expect_rc 0 "generate-one-dry-run" \
  "$TOOL" generate \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --import-file "$GOOD_IMPORT" \
  --sso-session Advantageous \
  --dry-run --non-interactive --force

echo "### Test 7: generate overwrite policy: conflict without --force -> error"
# Simulate existing managed block for Advantageous
{
  echo "### [START] configure-profiles.sh for Advantageous"
  echo "[sso-session adv]"
  echo "### [END] configure-profiles.sh for Advantageous"
} >>"$AWS_CFG"

expect_rc 1 "generate-conflict-no-force" \
  "$TOOL" generate \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --import-file "$GOOD_IMPORT" \
  --sso-session Advantageous \
  --dry-run --non-interactive

echo "### Test 8: generate overwrite policy: conflict with --force -> ok"
expect_rc 0 "generate-conflict-force" \
  "$TOOL" generate \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --import-file "$GOOD_IMPORT" \
  --sso-session Advantageous \
  --dry-run --non-interactive --force

echo
pass "All dry-run tests completed in $SANDBOX"
[[ -n "${TEST_KEEP:-}" ]] || echo "(sandbox removed)"
