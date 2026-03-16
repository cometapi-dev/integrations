#!/usr/bin/env bash
# =============================================================================
# test_setup_cometapi.sh — End-to-end tests for setup_cometapi.sh
# Dependencies: bash, node (same as the setup script itself)
# Cross-platform: macOS + Linux
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/../setup.sh"   # openclaw/setup.sh
TEST_DIR="$(mktemp -d)"
FAKE_HOME="${TEST_DIR}/fakehome"
FAKE_BIN="${TEST_DIR}/fakebin"
PASS=0; FAIL=0; TOTAL=0

cleanup() { rm -rf "${TEST_DIR}"; }
trap cleanup EXIT

# ─── Helpers ─────────────────────────────────────────────────────────────
ok()   { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf "  ✅ PASS: %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf "  ❌ FAIL: %s\n" "$1"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then ok "${desc}"
  else fail "${desc} (expected='${expected}', got='${actual}')"; fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "${haystack}" | grep -qF -- "${needle}"; then ok "${desc}"
  else fail "${desc} — missing '${needle}'"; fi
}

# Cross-platform JSON field reader using Node.js (no python/jq needed)
json_get() {
  local file="$1" key_path="$2"
  node -e "
    const d = JSON.parse(require('fs').readFileSync('${file}', 'utf-8'));
    const keys = '${key_path}'.split('.');
    let v = d;
    for (const k of keys) v = v[k];
    process.stdout.write(String(v));
  "
}

assert_json_field() {
  local desc="$1" file="$2" key_path="$3" expected="$4"
  local actual
  actual="$(json_get "${file}" "${key_path}")"
  assert_eq "${desc}" "${expected}" "${actual}"
}

# Check if a JSON key exists (returns "true"/"false")
json_has_key() {
  local file="$1" key_path="$2"
  node -e "
    const d = JSON.parse(require('fs').readFileSync('${file}', 'utf-8'));
    const keys = '${key_path}'.split('.');
    let v = d;
    for (const k of keys) { if (v == null || !(k in v)) { process.stdout.write('false'); process.exit(); } v = v[k]; }
    process.stdout.write('true');
  "
}

# Cross-platform file permission check (octal)
get_perms() {
  if stat -f '%Lp' "$1" 2>/dev/null; then
    return  # macOS (BSD stat)
  fi
  stat -c '%a' "$1" 2>/dev/null  # Linux (GNU stat)
}

# ─── Prepare mock environment ────────────────────────────────────────────
setup_env() {
  rm -rf "${FAKE_HOME}" "${FAKE_BIN}"
  mkdir -p "${FAKE_HOME}/.openclaw" "${FAKE_BIN}"

  # Mock openclaw binary
  cat > "${FAKE_BIN}/openclaw" <<'MOCKEOF'
#!/bin/sh
case "$1" in
  --version) echo "openclaw 2026.3.8-mock" ;;
  gateway)   echo "gateway ${2:-status}: ok (mock)" ;;
  *)         echo "openclaw mock: $*" ;;
esac
MOCKEOF
  chmod +x "${FAKE_BIN}/openclaw"
}

# Run the setup script with our mocked HOME and PATH
run_setup() {
  HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" \
    COMETAPI_KEY="$1" _SETUP_SKIP_VERIFY=1 \
    sh "${SETUP_SCRIPT}" 2>&1
}

# Run with --key flag instead of env var
run_setup_flag() {
  HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" \
    _SETUP_SKIP_VERIFY=1 \
    sh "${SETUP_SCRIPT}" --key "$1" 2>&1
}

# Run with arbitrary extra args
run_setup_args() {
  HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" \
    _SETUP_SKIP_VERIFY=1 \
    sh "${SETUP_SCRIPT}" "$@" 2>&1
}

# ═════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Test Suite: setup_cometapi.sh v2.0 (POSIX sh edition)"
echo "═══════════════════════════════════════════════════════════"

# ── Test 1: Fresh install — no existing .env or openclaw.json ────────────
echo ""
echo "── Test 1: Fresh install (empty ~/.openclaw) ──"
setup_env
OUTPUT="$(run_setup "sk-test1234567890fresh")"

# .env should exist with the key
ENV_CONTENT="$(cat "${FAKE_HOME}/.openclaw/.env")"
assert_contains "1a: .env contains COMETAPI_KEY" "${ENV_CONTENT}" "COMETAPI_KEY=sk-test1234567890fresh"

# .env permissions should be 600
PERMS="$(get_perms "${FAKE_HOME}/.openclaw/.env")"
assert_eq "1b: .env permissions are 600" "600" "${PERMS}"

# openclaw.json should exist and have all 4 providers
assert_json_field "1c: has cometapi-openai provider" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-openai.api" \
  "openai-completions"

assert_json_field "1d: has cometapi-claude provider" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-claude.api" \
  "anthropic-messages"

assert_json_field "1e: has cometapi-gemini provider" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-gemini.api" \
  "google-generative-ai"

assert_json_field "1f: has cometapi-openai-responses provider" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-openai-responses.api" \
  "openai-responses"

assert_json_field "1g: default model is cometapi-claude/claude-sonnet-4-6" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "agents.defaults.model.primary" \
  "cometapi-claude/claude-sonnet-4-6"

assert_json_field "1h: models.mode is merge" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.mode" \
  "merge"

assert_json_field "1i: baseUrl for openai provider" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-openai.baseUrl" \
  "https://api.cometapi.com/v1"

assert_json_field "1j: apiKey uses env var reference" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-openai.apiKey" \
  '${COMETAPI_KEY}'

# ── Test 2: Idempotency — run again with same key ───────────────────────
echo ""
echo "── Test 2: Idempotency (run same key again) ──"
OUTPUT2="$(run_setup "sk-test1234567890fresh")"

# .env should still have exactly ONE copy of COMETAPI_KEY
KEY_COUNT="$(grep -c '^COMETAPI_KEY=' "${FAKE_HOME}/.openclaw/.env")"
assert_eq "2a: .env has exactly 1 COMETAPI_KEY line" "1" "${KEY_COUNT}"

# JSON should still be valid and identical
assert_json_field "2b: provider still correct after re-run" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-claude.api" \
  "anthropic-messages"

# Count providers — should still be 4 cometapi providers
PROVIDER_COUNT="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const ps = Object.keys(d.models.providers).filter(k => k.startsWith('cometapi-'));
  process.stdout.write(String(ps.length));
")"
assert_eq "2c: still exactly 4 cometapi providers" "4" "${PROVIDER_COUNT}"

# ── Test 3: Key update — run with a different key ────────────────────────
echo ""
echo "── Test 3: Key update (new key replaces old) ──"
OUTPUT3="$(run_setup "sk-newkey999888777666")"

ENV_CONTENT3="$(cat "${FAKE_HOME}/.openclaw/.env")"
assert_contains "3a: .env has new key" "${ENV_CONTENT3}" "COMETAPI_KEY=sk-newkey999888777666"

KEY_COUNT3="$(grep -c '^COMETAPI_KEY=' "${FAKE_HOME}/.openclaw/.env")"
assert_eq "3b: still exactly 1 COMETAPI_KEY line after key update" "1" "${KEY_COUNT3}"

# ── Test 4: Non-destructive — existing providers not touched ─────────────
echo ""
echo "── Test 4: Non-destructive (existing providers preserved) ──"
setup_env

# Pre-populate openclaw.json with existing provider
cat > "${FAKE_HOME}/.openclaw/openclaw.json" <<'EXISTING'
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai/gpt-4o"
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "openai": {
        "baseUrl": "https://api.openai.com/v1",
        "apiKey": "${OPENAI_API_KEY}",
        "api": "openai-completions",
        "models": [{"id": "gpt-4o", "name": "GPT-4o"}]
      },
      "anthropic": {
        "baseUrl": "https://api.anthropic.com",
        "apiKey": "${ANTHROPIC_API_KEY}",
        "api": "anthropic-messages",
        "models": [{"id": "claude-3-opus", "name": "Claude 3 Opus"}]
      }
    }
  },
  "customSetting": "do-not-touch"
}
EXISTING

# Pre-populate .env with existing vars
cat > "${FAKE_HOME}/.openclaw/.env" <<'ENVEXIST'
OPENAI_API_KEY=sk-openai-xxx
ANTHROPIC_API_KEY=sk-anthropic-yyy
ENVEXIST

OUTPUT4="$(run_setup "sk-comet4444333322221111")"

# Existing providers must be untouched
assert_json_field "4a: openai provider untouched" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.openai.apiKey" \
  '${OPENAI_API_KEY}'

assert_json_field "4b: anthropic provider untouched" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.anthropic.apiKey" \
  '${ANTHROPIC_API_KEY}'

# Custom top-level keys must be preserved
assert_json_field "4c: customSetting preserved" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "customSetting" \
  "do-not-touch"

# Existing default model should NOT be overwritten
assert_json_field "4d: existing default model preserved" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "agents.defaults.model.primary" \
  "openai/gpt-4o"

# CometAPI providers should now also be present
assert_json_field "4e: cometapi-openai added alongside existing" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-openai.api" \
  "openai-completions"

# Existing .env vars must be preserved
ENV_CONTENT4="$(cat "${FAKE_HOME}/.openclaw/.env")"
assert_contains "4f: OPENAI_API_KEY preserved in .env" "${ENV_CONTENT4}" "OPENAI_API_KEY=sk-openai-xxx"
assert_contains "4g: ANTHROPIC_API_KEY preserved in .env" "${ENV_CONTENT4}" "ANTHROPIC_API_KEY=sk-anthropic-yyy"
assert_contains "4h: COMETAPI_KEY added" "${ENV_CONTENT4}" "COMETAPI_KEY=sk-comet4444333322221111"

# Total provider count should be 6 (2 existing + 4 cometapi)
TOTAL_PROVIDERS="$(node -e "
  const d=JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  process.stdout.write(String(Object.keys(d.models.providers).length));
")"
assert_eq "4i: total 6 providers (2 existing + 4 cometapi)" "6" "${TOTAL_PROVIDERS}"

# ── Test 5: User-added models preserved in cometapi providers ────────────
echo ""
echo "── Test 5: User-added models preserved on re-run ──"
setup_env

# Pre-populate with cometapi-openai that has a user-added model
cat > "${FAKE_HOME}/.openclaw/openclaw.json" <<'USERMODEL'
{
  "models": {
    "mode": "merge",
    "providers": {
      "cometapi-openai": {
        "baseUrl": "https://api.cometapi.com/v1",
        "apiKey": "${COMETAPI_KEY}",
        "api": "openai-completions",
        "models": [
          {"id": "gpt-5.4", "name": "GPT-5.4"},
          {"id": "o3-mini", "name": "o3-mini (user added)"}
        ]
      }
    }
  }
}
USERMODEL

OUTPUT5="$(run_setup "sk-test5555555555555555")"

# The user-added model "o3-mini" should still be present, no duplicates
MODEL_CHECK="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-openai'].models;
  const ids = models.map(m => m.id);
  const hasO3 = ids.includes('o3-mini');
  const hasGpt54 = ids.includes('gpt-5.4');
  const gpt54Count = ids.filter(x => x === 'gpt-5.4').length;
  console.log(JSON.stringify({hasO3, hasGpt54, gpt54Count}));
")"

O3_PRESENT="$(echo "${MODEL_CHECK}" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')); process.stdout.write(String(d.hasO3))")"
GPT54_PRESENT="$(echo "${MODEL_CHECK}" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')); process.stdout.write(String(d.hasGpt54))")"
GPT54_COUNT="$(echo "${MODEL_CHECK}" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')); process.stdout.write(String(d.gpt54Count))")"

assert_eq "5a: user-added model o3-mini preserved" "true" "${O3_PRESENT}"
assert_eq "5b: default model gpt-5.4 still present" "true" "${GPT54_PRESENT}"
assert_eq "5c: no duplicate gpt-5.4 entries" "1" "${GPT54_COUNT}"

# ── Test 6: Invalid key rejected ─────────────────────────────────────────
echo ""
echo "── Test 6: Invalid key rejection ──"
setup_env

# Too short
OUTPUT6="$(run_setup "sk-abc" 2>&1 || true)"
assert_contains "6a: rejects short key" "${OUTPUT6}" "Invalid key format"
assert_contains "6a2: shows key URL on rejection" "${OUTPUT6}" "www.cometapi.com/console/token"

# Missing sk- prefix
OUTPUT7="$(run_setup "notavalidkey123456" 2>&1 || true)"
assert_contains "6b: rejects key without sk- prefix" "${OUTPUT7}" "Invalid key format"

# ── Test 7: Missing openclaw directory ───────────────────────────────────
echo ""
echo "── Test 7: Missing ~/.openclaw directory ──"
rm -rf "${FAKE_HOME}/.openclaw"
OUTPUT8="$(run_setup "sk-validkey1234567890" 2>&1 || true)"
assert_contains "7a: error when ~/.openclaw missing" "${OUTPUT8}" "does not exist"

# ── Test 8: Missing openclaw CLI ─────────────────────────────────────────
echo ""
echo "── Test 8: Missing openclaw CLI ──"
setup_env
rm -f "${FAKE_BIN}/openclaw"
OUTPUT9="$(HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/local/bin" COMETAPI_KEY="sk-validkey1234567890" _SETUP_SKIP_VERIFY=1 sh "${SETUP_SCRIPT}" 2>&1 || true)"
assert_contains "8a: error when openclaw not in PATH" "${OUTPUT9}" "OpenClaw CLI not found"

# ── Test 9: Corrupted JSON backup ────────────────────────────────────────
echo ""
echo "── Test 9: Corrupted JSON handled gracefully ──"
setup_env
echo "NOT VALID JSON {{{" > "${FAKE_HOME}/.openclaw/openclaw.json"
OUTPUT10="$(run_setup "sk-testcorrupt12345678")"
assert_contains "9a: warns about invalid JSON" "${OUTPUT10}" "Invalid JSON"

# Should have created a .bak
if [[ -f "${FAKE_HOME}/.openclaw/openclaw.json.bak" ]]; then ok "9b: backup file created"
else fail "9b: backup file created"; fi

# New config should be valid and have providers
assert_json_field "9c: fresh config created after corruption" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-claude.api" \
  "anthropic-messages"

# ── Test 10: Idempotency stress — 5 consecutive runs ────────────────────
echo ""
echo "── Test 10: Idempotency stress (5 consecutive runs) ──"
setup_env
for i in 1 2 3 4 5; do
  run_setup "sk-stress1234567890abc" > /dev/null
done

KEY_COUNT10="$(grep -c '^COMETAPI_KEY=' "${FAKE_HOME}/.openclaw/.env")"
assert_eq "10a: .env has exactly 1 key after 5 runs" "1" "${KEY_COUNT10}"

PROVIDER_COUNT10="$(node -e "
  const d=JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const ps=Object.keys(d.models.providers).filter(k=>k.startsWith('cometapi-'));
  process.stdout.write(String(ps.length));
")"
assert_eq "10b: still exactly 4 cometapi providers after 5 runs" "4" "${PROVIDER_COUNT10}"

# JSON file should be valid
node -e "JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'))" 2>/dev/null
if [[ $? -eq 0 ]]; then ok "10c: JSON still valid after 5 runs"
else fail "10c: JSON still valid after 5 runs"; fi

# ── Test 11: Missing node CLI ────────────────────────────────────────────
echo ""
echo "── Test 11: Missing node CLI ──"
setup_env
# Run with a PATH that has no node — also clear NVM_DIR/BASH_ENV to prevent
# nvm shell init from re-adding node to PATH
OUTPUT11="$(HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:/usr/bin:/bin" NVM_DIR="" BASH_ENV="" COMETAPI_KEY="sk-validkey1234567890" _SETUP_SKIP_VERIFY=1 bash --norc --noprofile "${SETUP_SCRIPT}" 2>&1 || true)"
assert_contains "11a: error when node not in PATH" "${OUTPUT11}" "Node.js is required"

# ── Test 12: --key flag ──────────────────────────────────────────────────
echo ""
echo "── Test 12: --key flag ──"
setup_env
OUTPUT12="$(run_setup_flag "sk-flag1234567890xyz")"
ENV_CONTENT12="$(cat "${FAKE_HOME}/.openclaw/.env")"
assert_contains "12a: --key flag sets key correctly" "${ENV_CONTENT12}" "COMETAPI_KEY=sk-flag1234567890xyz"

# ── Test 13: --dry-run does not write files ──────────────────────────────
echo ""
echo "── Test 13: --dry-run mode ──"
setup_env
OUTPUT13="$(HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" _SETUP_SKIP_VERIFY=1 sh "${SETUP_SCRIPT}" --key sk-dryrun1234567890 --dry-run 2>&1)"
assert_contains "13a: output mentions DRY RUN" "${OUTPUT13}" "DRY RUN"

# .env should NOT exist (fresh env, dry run should not create it)
if [[ ! -f "${FAKE_HOME}/.openclaw/.env" ]]; then ok "13b: .env not created in dry-run"
else fail "13b: .env not created in dry-run"; fi

# openclaw.json should NOT exist
if [[ ! -f "${FAKE_HOME}/.openclaw/openclaw.json" ]]; then ok "13c: openclaw.json not created in dry-run"
else fail "13c: openclaw.json not created in dry-run"; fi

# ── Test 14: --help flag ─────────────────────────────────────────────────
echo ""
echo "── Test 14: --help flag ──"
OUTPUT14="$(HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" sh "${SETUP_SCRIPT}" --help 2>&1)"
assert_contains "14a: help shows usage" "${OUTPUT14}" "Usage:"
assert_contains "14b: help shows --key" "${OUTPUT14}" "--key"
assert_contains "14c: help shows --dry-run" "${OUTPUT14}" "--dry-run"

# ── Test 15: --version flag ─────────────────────────────────────────────
echo ""
echo "── Test 15: --version flag ──"
OUTPUT15="$(HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" sh "${SETUP_SCRIPT}" --version 2>&1)"
assert_contains "15a: version output" "${OUTPUT15}" "setup_cometapi.sh v"

# ── Test 16: --add-model adds model to existing provider ────────────────
echo ""
echo "── Test 16: --add-model flag ──"
setup_env
OUTPUT16="$(run_setup_args --key sk-addmodel12345678 --add-model cometapi-openai/gpt-5.2-chat-latest)"
assert_contains "16a: output confirms model added" "${OUTPUT16}" "gpt-5.2-chat-latest"

# Verify model is in the JSON
HAS_MODEL="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-openai'].models;
  process.stdout.write(String(models.some(m => m.id === 'gpt-5.2-chat-latest')));
")"
assert_eq "16b: model gpt-5.2-chat-latest added to cometapi-openai" "true" "${HAS_MODEL}"

# Default model should still be there
HAS_DEFAULT="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-openai'].models;
  process.stdout.write(String(models.some(m => m.id === 'gpt-5.4')));
")"
assert_eq "16c: default model gpt-5.4 still present" "true" "${HAS_DEFAULT}"

# ── Test 17: --add-model multiple models at once ────────────────────────
echo ""
echo "── Test 17: --add-model multiple providers ──"
setup_env
OUTPUT17="$(run_setup_args --key sk-multi12345678901 \
  --add-model cometapi-claude/claude-sonnet-4-6 \
  --add-model cometapi-gemini/gemini-3.1-pro)"

CLAUDE_HAS="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-claude'].models;
  process.stdout.write(String(models.some(m => m.id === 'claude-sonnet-4-6')));
")"
# claude-sonnet-4-6 is a default model, should already exist (not duplicated)
assert_eq "17a: claude-sonnet-4-6 present (default)" "true" "${CLAUDE_HAS}"

GEMINI_HAS="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-gemini'].models;
  process.stdout.write(String(models.some(m => m.id === 'gemini-3.1-pro')));
")"
assert_eq "17b: gemini-3.1-pro added to cometapi-gemini" "true" "${GEMINI_HAS}"

# No duplicate of default
CLAUDE_COUNT="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-claude'].models;
  process.stdout.write(String(models.filter(m => m.id === 'claude-sonnet-4-6').length));
")"
assert_eq "17c: no duplicate claude-sonnet-4-6" "1" "${CLAUDE_COUNT}"

# ── Test 18: --add-model invalid provider ────────────────────────────────
echo ""
echo "── Test 18: --add-model invalid provider ──"
setup_env
OUTPUT18="$(run_setup_args --key sk-invprov1234567890 --add-model invalid-provider/some-model 2>&1 || true)"
assert_contains "18a: warns about unknown provider" "${OUTPUT18}" "Unknown provider"

# ── Test 19: --add-model invalid format ──────────────────────────────────
echo ""
echo "── Test 19: --add-model invalid format ──"
setup_env
OUTPUT19="$(run_setup_args --key sk-invfmt12345678901 --add-model no-slash 2>&1 || true)"
assert_contains "19a: rejects invalid format" "${OUTPUT19}" "Invalid --add-model"

# ── Test 20: cometapi-google → cometapi-gemini migration ─────────────────
echo ""
echo "── Test 20: Migration cometapi-google → cometapi-gemini ──"
setup_env

# Pre-populate with the old cometapi-google name
cat > "${FAKE_HOME}/.openclaw/openclaw.json" <<'OLDGOOGLE'
{
  "models": {
    "mode": "merge",
    "providers": {
      "cometapi-google": {
        "baseUrl": "https://api.cometapi.com/v1beta",
        "apiKey": "${COMETAPI_KEY}",
        "api": "google-generative-ai",
        "models": [
          {"id": "gemini-3.1-pro-preview", "name": "Gemini 3.1 Pro"},
          {"id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash (user added)"}
        ]
      }
    }
  }
}
OLDGOOGLE

OUTPUT20="$(run_setup "sk-migrate1234567890x")"
assert_contains "20a: migration message shown" "${OUTPUT20}" "cometapi-google"

# cometapi-google should be gone
HAS_OLD="$(json_has_key "${FAKE_HOME}/.openclaw/openclaw.json" "models.providers.cometapi-google")"
assert_eq "20b: cometapi-google removed" "false" "${HAS_OLD}"

# cometapi-gemini should exist with the merged content
assert_json_field "20c: cometapi-gemini exists after migration" \
  "${FAKE_HOME}/.openclaw/openclaw.json" \
  "models.providers.cometapi-gemini.api" \
  "google-generative-ai"

# User-added model from the old cometapi-google should be preserved
USER_FLASH="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-gemini'].models;
  process.stdout.write(String(models.some(m => m.id === 'gemini-2.0-flash')));
")"
assert_eq "20d: user model gemini-2.0-flash preserved after migration" "true" "${USER_FLASH}"

# ── Test 21: --add-model dedup — adding a model that already exists ──────
echo ""
echo "── Test 21: --add-model deduplication ──"
setup_env
run_setup_args --key sk-dedup12345678901 --add-model cometapi-openai/gpt-5.2-chat-latest > /dev/null
OUTPUT21="$(run_setup_args --key sk-dedup12345678901 --add-model cometapi-openai/gpt-5.2-chat-latest)"
assert_contains "21a: output says already exists" "${OUTPUT21}" "already exists"

MODEL_COUNT_DEDUP="$(node -e "
  const d = JSON.parse(require('fs').readFileSync('${FAKE_HOME}/.openclaw/openclaw.json','utf-8'));
  const models = d.models.providers['cometapi-openai'].models;
  process.stdout.write(String(models.filter(m => m.id === 'gpt-5.2-chat-latest').length));
")"
assert_eq "21b: no duplicate gpt-5.2-chat-latest" "1" "${MODEL_COUNT_DEDUP}"

# ── Test 22: --help mentions --add-model ─────────────────────────────────
echo ""
echo "── Test 22: --help includes --add-model ──"
OUTPUT22="$(HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" sh "${SETUP_SCRIPT}" --help 2>&1)"
assert_contains "22a: help shows --add-model" "${OUTPUT22}" "--add-model"
assert_contains "22b: help shows cometapi-gemini" "${OUTPUT22}" "cometapi-gemini"

# ═════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════"
printf "  Results: %d passed, %d failed, %d total\n" "${PASS}" "${FAIL}" "${TOTAL}"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
else
  echo "  All tests passed! ✨"
  exit 0
fi
