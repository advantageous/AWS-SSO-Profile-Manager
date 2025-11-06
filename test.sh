#!/usr/bin/env bash
set -euo pipefail

TOOL="./aws-sso-profile"   # adjust if needed

pass() { printf "✅ %s\n" "$*"; }
fail() { printf "❌ %s\n" "$*"; exit 1; }
note() { printf "ℹ️  %s\n" "$*"; }

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

# Test fixture files
GOOD_IMPORT="$SANDBOX/good-import.yaml"
BAD_IMPORT="$SANDBOX/bad-import.yaml"
BAD_REGION="$SANDBOX/bad-region.yaml"
BAD_URL="$SANDBOX/bad-url.yaml"
CHINA_REGION="$SANDBOX/china-region.yaml"
MIXED_VALID="$SANDBOX/mixed-valid.yaml"

# Seed files
cat >"$GOOD_IMPORT" <<'YAML'
ev:
  start_url: https://d-1067f984aa.awsapps.com/start
  sso_region: us-east-1
adv:
  start_url: https://advantageous.awsapps.com/start
  sso_region: eu-central-1
YAML

cat >"$BAD_IMPORT" <<'YAML'
BrokenCo:
  # start_url missing on purpose
  sso_region: us-west-2
YAML

cat >"$BAD_REGION" <<'YAML'
BadRegion:
  start_url: https://test.awsapps.com/start
  sso_region: invalid-region
YAML

cat >"$BAD_URL" <<'YAML'
BadURL:
  start_url: http://not-secure.awsapps.com/start
  sso_region: us-east-1
BadURL2:
  start_url: https://wrong-domain.com/start
  sso_region: us-west-2
YAML

cat >"$CHINA_REGION" <<'YAML'
ChinaNorth:
  start_url: https://start.cn-north-1.home.awsapps.cn/directory/d-8267160432
  sso_region: cn-north-1
ChinaNorthwest:
  start_url: https://start.cn-northwest-1.home.awsapps.cn/directory/d-1234567890
  sso_region: cn-northwest-1
YAML

cat >"$MIXED_VALID" <<'YAML'
Standard:
  start_url: https://myorg.awsapps.com/start
  sso_region: us-west-2
China:
  start_url: https://start.cn-north-1.home.awsapps.cn/directory/d-123456
  sso_region: cn-north-1
YAML

: >"$SESS_STORE"   # empty sessions store
: >"$AWS_CFG"      # empty aws config

# Run a command, capture rc and output
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
  return 0
}

# Run and capture output
run_with_output() {
  local name="$1"; shift
  set +e
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  set -e
  if [[ -n "${TEST_VERBOSE:-}" ]]; then
    printf '%s\n' "$out" | sed 's/^/  | /' >&2
  fi
  echo "$out"
  return "$rc"
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

expect_output_contains() {
  local pattern="$1"; shift
  local name="$1"; shift
  local output
  output="$(run_with_output "$name" "$@")" || true
  if grep -qF "$pattern" <<<"$output"; then
    pass "$name (found: '$pattern')"
  else
    echo "Expected output to contain: $pattern"
    echo "Actual output:"
    echo "$output"
    fail "$name - pattern not found in output"
  fi
}

# =====================
# Test Suite
# =====================

echo "=== Basic Functionality Tests ==="

echo "### Test 1: --version flag"
expect_rc 0 "version-flag" "$TOOL" --version

echo "### Test 2: --help flag"
expect_rc 0 "help-flag" "$TOOL" --help

echo "### Test 3: -h flag"
expect_rc 0 "h-flag" "$TOOL" -h

echo "### Test 4: help command"
expect_rc 0 "help-command" "$TOOL" help

echo "### Test 5: invalid command"
expect_rc 1 "invalid-command" "$TOOL" notacommand

echo
echo "=== Configure Import Tests ==="

echo "### Test 6: configure --import-file (all sessions) dry-run ok"
expect_rc 0 "configure-import-all-dry-run" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive --force

echo "### Test 7: configure conflict without --force in non-interactive -> error"
# First, actually write once (no dry-run) so conflicts exist
"$TOOL" configure --config-file "$SESS_STORE" --import-file "$GOOD_IMPORT" --non-interactive --force >/dev/null
expect_rc 1 "configure-conflict-no-force" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive

echo "### Test 8: configure conflict with --force in non-interactive -> ok"
expect_rc 0 "configure-conflict-force" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive --force

echo "### Test 9: configure fail on missing fields"
expect_rc 1 "configure-missing-fields" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$BAD_IMPORT" \
  --dry-run --non-interactive

echo
echo "=== Validation Tests ==="

echo "### Test 10: configure reject invalid region format"
expect_rc 1 "configure-invalid-region" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$BAD_REGION" \
  --dry-run --non-interactive --force

echo "### Test 11: configure reject invalid URL format (http)"
expect_rc 1 "configure-invalid-url-http" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$BAD_URL" \
  --dry-run --non-interactive --force

echo "### Test 12: configure accept China region URLs"
expect_rc 0 "configure-china-region" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$CHINA_REGION" \
  --dry-run --non-interactive --force

echo "### Test 13: configure accept mixed standard and China regions"
expect_rc 0 "configure-mixed-regions" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$MIXED_VALID" \
  --dry-run --non-interactive --force

echo "### Test 14: validate error message contains helpful info for bad region"
expect_output_contains "us-east-1" "error-message-region" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$BAD_REGION" \
  --dry-run --non-interactive --force

echo "### Test 15: validate error message contains helpful info for bad URL"
expect_output_contains "awsapps.com" "error-message-url" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$BAD_URL" \
  --dry-run --non-interactive --force

echo
echo "=== List Command Tests ==="

echo "### Test 16: list from --import-file"
expect_rc 0 "list-from-import" \
  "$TOOL" list \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT"

echo "### Test 17: list shows correct session names"
expect_output_contains "adv" "list-contains-name" \
  "$TOOL" list \
  --config-file "$SESS_STORE" \
  --import-file "$GOOD_IMPORT"

echo "### Test 18: list with no sessions file returns gracefully"
NEW_STORE="$SANDBOX/empty-store.yaml"
expect_rc 0 "list-no-sessions" \
  "$TOOL" list \
  --config-file "$NEW_STORE"

echo
echo "=== Generate Command Tests (Dry-Run) ==="

echo "### Test 19: generate for one key from --import-file (no existing block) ok"
expect_rc 0 "generate-one-dry-run" \
  "$TOOL" generate \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --import-file "$GOOD_IMPORT" \
  --sso-session adv \
  --dry-run --non-interactive --force

echo "### Test 20: generate overwrite policy: conflict without --force -> error"
# Simulate existing managed block for Advantageous
{
  echo "### [START] AWS-SSO-Profile-Manager for adv"
  echo "[sso-session adv]"
  echo "### [END] AWS-SSO-Profile-Manager for adv"
} >>"$AWS_CFG"

expect_rc 1 "generate-conflict-no-force" \
  "$TOOL" generate \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --import-file "$GOOD_IMPORT" \
  --sso-session adv \
  --dry-run --non-interactive

echo "### Test 21: generate overwrite policy: conflict with --force -> ok"
expect_rc 0 "generate-conflict-force" \
  "$TOOL" generate \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --import-file "$GOOD_IMPORT" \
  --sso-session adv \
  --dry-run --non-interactive --force

echo
echo "=== Clear Command Tests ==="

echo "### Test 22: clear specific session"
# First add a managed block
{
  echo "### [START] AWS-SSO-Profile-Manager for TestSession"
  echo "[sso-session TestSession]"
  echo "### [END] AWS-SSO-Profile-Manager for TestSession"
} > "$AWS_CFG"

expect_rc 0 "clear-specific-session" \
  "$TOOL" clear \
  --config-file "$SESS_STORE" \
  --output-file "$AWS_CFG" \
  --sso-session TestSession

echo "### Test 23: verify cleared content is removed"
if [[ -f "$AWS_CFG" ]] && grep -q "TestSession" "$AWS_CFG"; then
  fail "clear did not remove TestSession content"
else
  pass "clear successfully removed TestSession"
fi

echo
echo "=== Flag Handling Tests ==="

echo "### Test 24: unknown flag returns error"
expect_rc 1 "unknown-flag" \
  "$TOOL" configure --unknown-flag

echo "### Test 25: missing value for --sso-session"
expect_rc 1 "missing-sso-session-value" \
  "$TOOL" list --sso-session

echo "### Test 26: missing value for --config-file"
expect_rc 1 "missing-config-file-value" \
  "$TOOL" list --config-file

echo
echo "=== Edge Cases ==="

echo "### Test 27: handle session name with special characters in YAML"
cat >"$SANDBOX/special-chars.yaml" <<'YAML'
My-Org_123:
  start_url: https://my-org.awsapps.com/start
  sso_region: us-east-1
YAML

expect_rc 0 "special-chars-in-name" \
  "$TOOL" configure \
  --config-file "$SESS_STORE" \
  --import-file "$SANDBOX/special-chars.yaml" \
  --dry-run --non-interactive --force

echo "### Test 28: empty YAML file"
: >"$SANDBOX/empty.yaml"
expect_rc 0 "empty-yaml" \
  "$TOOL" list \
  --config-file "$SESS_STORE" \
  --import-file "$SANDBOX/empty.yaml"

echo "### Test 29: YAML with only whitespace"
echo "   " >"$SANDBOX/whitespace.yaml"
expect_rc 0 "whitespace-yaml" \
  "$TOOL" list \
  --config-file "$SESS_STORE" \
  --import-file "$SANDBOX/whitespace.yaml"

echo
echo "=== File Operations Tests ==="

echo "### Test 30: creates parent directories for config files"
NESTED_CFG="$SANDBOX/deeply/nested/path/sessions.yaml"
expect_rc 0 "create-nested-dirs" \
  "$TOOL" configure \
  --config-file "$NESTED_CFG" \
  --import-file "$GOOD_IMPORT" \
  --dry-run --non-interactive --force

if [[ -d "$(dirname "$NESTED_CFG")" ]]; then
  pass "parent directories created"
else
  fail "parent directories not created"
fi

echo
echo "=== Summary ==="
pass "All tests completed in $SANDBOX"
[[ -n "${TEST_KEEP:-}" ]] || note "sandbox will be removed on exit"
