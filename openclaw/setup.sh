#!/bin/sh
# =============================================================================
# setup_cometapi.sh — One-click CometAPI provider setup for OpenClaw
#
# Adds CometAPI as a model provider to your local OpenClaw installation.
# Does NOT install OpenClaw itself.
#
# Usage:
#   curl -fsSL https://docs.cometapi.com/setup-openclaw.sh | sh
#   sh setup_cometapi.sh
#   sh setup_cometapi.sh --key sk-xxxxx
#   sh setup_cometapi.sh --add-model cometapi-openai/gpt-5.2-chat-latest
#   sh setup_cometapi.sh --dry-run
#   sh setup_cometapi.sh --help
#
# What it does:
#   1. Verifies OpenClaw + Node.js are installed
#   2. Prompts for your CometAPI API key (or reads from --key / env)
#   3. Writes the key to ~/.openclaw/.env (idempotent)
#   4. Merges CometAPI provider blocks into ~/.openclaw/openclaw.json
#      — existing providers and settings are NEVER modified or removed
#   5. Restarts the OpenClaw gateway
#
# Platform:    macOS, Linux, WSL, Git Bash (POSIX sh compatible)
# Windows:     Use setup_cometapi.ps1 for native PowerShell
# Deps:        sh (POSIX), node >= 18 (guaranteed by OpenClaw)
# No Python, jq, sed -i, or GNU/BSD-specific tools required.
#
# References:
#   CometAPI docs          https://docs.cometapi.com
#   CometAPI + OpenClaw    https://docs.cometapi.com/integrations/openclaw
#   OpenClaw               https://openclaw.ai
#   Get API key            https://www.cometapi.com/console/token
# =============================================================================

set -eu

# ─── Constants ───────────────────────────────────────────────────────────────
SCRIPT_VERSION="2.0.0"
OPENCLAW_DIR="${HOME}/.openclaw"
ENV_FILE="${OPENCLAW_DIR}/.env"
CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
ENV_VAR_NAME="COMETAPI_KEY"

_BASE_URL_OPENAI="https://api.cometapi.com/v1"
_BASE_URL_ANTHROPIC="https://api.cometapi.com"
_BASE_URL_GEMINI="https://api.cometapi.com/v1beta"

# ─── Color support ──────────────────────────────────────────────────────────
# Follows NO_COLOR (https://no-color.org) and detects dumb terminals.
setup_colors() {
  if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
  else
    GREEN=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; DIM=''; RESET=''
  fi
}
setup_colors

# ─── Output helpers ─────────────────────────────────────────────────────────
info()    { printf "  %b✅  %s%b\n"  "$GREEN"  "$*"  "$RESET"; }
warn()    { printf "  %b⚠️   %s%b\n"  "$YELLOW" "$*"  "$RESET"; }
err()     { printf "  %b❌  %s%b\n"  "$RED"    "$*"  "$RESET" >&2; }
step()    { printf "\n%b%b🔧 %s%b\n"  "$BOLD" "$CYAN" "$*" "$RESET"; }
header()  { printf "\n%b%b%s%b\n"     "$BOLD" "$CYAN" "$*" "$RESET"; }
detail()  { printf "     %b%s%b\n"    "$DIM"  "$*"  "$RESET"; }

# ─── Parse arguments ────────────────────────────────────────────────────────
ARG_KEY=""
DRY_RUN=0
ADD_MODELS=""  # comma-separated "provider/model-id" pairs

show_help() {
  cat <<'HELPEOF'
Usage: sh setup_cometapi.sh [OPTIONS]

🚀 Add CometAPI as a model provider to your local OpenClaw installation.

Options:
  --key KEY                Provide CometAPI API key non-interactively
  --add-model PROV/MODEL   Add a model to a CometAPI provider (repeatable)
  --dry-run                Show what would be changed without writing any files
  --help, -h               Show this help message
  --version                Show script version

Provider names for --add-model:
  cometapi-openai            OpenAI Chat Completions
  cometapi-openai-responses  OpenAI Responses API
  cometapi-claude            Anthropic Messages
  cometapi-gemini            Google Generative AI

Environment variables:
  COMETAPI_KEY   Same as --key (--key takes precedence)
  NO_COLOR       Disable colored output (https://no-color.org)

Examples:
  sh setup_cometapi.sh                                              # interactive
  sh setup_cometapi.sh --key sk-xxxxx                               # non-interactive
  sh setup_cometapi.sh --add-model cometapi-openai/gpt-5.2-chat-latest
  sh setup_cometapi.sh --add-model cometapi-claude/claude-sonnet-4-6 \
                       --add-model cometapi-gemini/gemini-3.1-pro

Windows users: use setup_cometapi.ps1 instead.
Full docs: https://docs.cometapi.com/integrations/openclaw
HELPEOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --key)
      if [ $# -lt 2 ]; then err "--key requires a value"; exit 1; fi
      ARG_KEY="$2"; shift 2 ;;
    --key=*)
      ARG_KEY="${1#*=}"; shift ;;
    --add-model)
      if [ $# -lt 2 ]; then err "--add-model requires provider/model-id"; exit 1; fi
      if [ -z "$ADD_MODELS" ]; then ADD_MODELS="$2"; else ADD_MODELS="${ADD_MODELS},$2"; fi
      shift 2 ;;
    --add-model=*)
      _val="${1#*=}"
      if [ -z "$ADD_MODELS" ]; then ADD_MODELS="$_val"; else ADD_MODELS="${ADD_MODELS},$_val"; fi
      shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --help|-h)  show_help ;;
    --version)  echo "setup_cometapi.sh v${SCRIPT_VERSION}"; exit 0 ;;
    -*)         err "Unknown option: $1 (try --help)"; exit 1 ;;
    *)          # Positional: treat as key for backward compat
                ARG_KEY="$1"; shift ;;
  esac
done

# Validate --add-model format: each must be "provider/model-id"
if [ -n "$ADD_MODELS" ]; then
  _IFS_BAK="$IFS"; IFS=","
  for _pair in $ADD_MODELS; do
    case "$_pair" in
      */*)  ;;  # valid
      *)    err "Invalid --add-model format: '$_pair' (expected: provider/model-id)"; exit 1 ;;
    esac
  done
  IFS="$_IFS_BAK"
fi

# ─── Pre-flight checks ──────────────────────────────────────────────────────
header "🔍 Pre-flight checks"

# 1. Node.js (guaranteed by OpenClaw's Node >= 22 requirement)
if ! command -v node >/dev/null 2>&1; then
  err "Node.js is required but not found."
  echo ""
  echo "   OpenClaw requires Node.js >= 22. Install via:"
  echo ""
  echo "     macOS/Linux:  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
  echo "                   nvm install 22"
  echo "     Windows:      https://nodejs.org/en/download"
  echo ""
  exit 1
fi
NODE_VER="$(node --version 2>&1 || echo 'unknown')"
info "Node.js ${NODE_VER}"

# 2. OpenClaw CLI
if ! command -v openclaw >/dev/null 2>&1; then
  err "OpenClaw CLI not found in PATH."
  echo ""
  echo "   Install OpenClaw first, then re-run this script:"
  echo ""
  echo "     curl -fsSL https://openclaw.ai/install.sh | bash"
  echo "     # — or —"
  echo "     npm install -g openclaw@latest"
  echo ""
  echo "   Then run the onboarding wizard:"
  echo ""
  echo "     openclaw onboard --install-daemon"
  echo ""
  echo "   Full guide: https://openclaw.ai"
  exit 1
fi
OPENCLAW_VER="$(openclaw --version 2>&1 || echo 'ok')"
info "OpenClaw ${OPENCLAW_VER}"

# 3. ~/.openclaw directory (created by onboarding)
if [ ! -d "${OPENCLAW_DIR}" ]; then
  err "Directory ${OPENCLAW_DIR} does not exist."
  echo ""
  echo "   Run the OpenClaw onboarding first:"
  echo ""
  echo "     openclaw onboard --install-daemon"
  echo ""
  echo "   Then re-run this script."
  exit 1
fi
info "Config directory: ${OPENCLAW_DIR}"

# ─── Resolve API key ────────────────────────────────────────────────────────
header "🔑 CometAPI API Key"

_KEY_URL="https://www.cometapi.com/console/token"
echo ""
detail "Get your key at: ${_KEY_URL}"
echo ""

# Priority: --key flag > COMETAPI_KEY env > interactive prompt
COMETAPI_KEY="${ARG_KEY:-${COMETAPI_KEY:-}}"

_IS_INTERACTIVE=0
if [ -z "${COMETAPI_KEY}" ]; then
  if [ ! -t 0 ]; then
    err "No API key provided and stdin is not a terminal (piped mode)."
    echo "   Use: curl ... | sh -s -- --key sk-xxxxx"
    exit 1
  fi
  _IS_INTERACTIVE=1
fi

# ─── Key input + format validation (interactive: up to 3 attempts) ──────────
_KEY_ATTEMPTS=0
_MAX_KEY_ATTEMPTS=3

while true; do
  if [ "${_IS_INTERACTIVE}" = "1" ]; then
    printf "  🔐 Enter your CometAPI API key (sk-…): "
    read -r COMETAPI_KEY
  fi

  _KEY_ATTEMPTS=$((_KEY_ATTEMPTS + 1))

  # Validate: must start with "sk-" and be at least 10 chars long
  case "${COMETAPI_KEY}" in
    sk-???????*) break ;;  # Valid: starts with sk- and at least 10 chars total
    *)
      if [ "${_IS_INTERACTIVE}" = "1" ]; then
        if [ "${_KEY_ATTEMPTS}" -ge "${_MAX_KEY_ATTEMPTS}" ]; then
          err "Invalid key format (${_KEY_ATTEMPTS}/${_MAX_KEY_ATTEMPTS}). Exiting."
          echo ""
          echo "   Go to ${_KEY_URL} to copy or create an API key."
          echo ""
          exit 1
        fi
        warn "Invalid key format (${_KEY_ATTEMPTS}/${_MAX_KEY_ATTEMPTS}). A CometAPI key starts with 'sk-' and is at least 10 characters."
        echo ""
        echo "   👉 Copy your key from: ${_KEY_URL}"
        echo ""
      else
        err "Invalid key format. A CometAPI key starts with 'sk-' and is at least 10 characters."
        echo ""
        echo "   Go to ${_KEY_URL} to copy or create an API key."
        echo ""
        exit 1
      fi
      ;;
  esac
done

# Show safe preview (first 6 + last 4 chars)
KEY_LEN=${#COMETAPI_KEY}
KEY_PREFIX="$(echo "${COMETAPI_KEY}" | cut -c1-6)"
KEY_SUFFIX="$(echo "${COMETAPI_KEY}" | cut -c$((KEY_LEN - 3))-${KEY_LEN})"
info "Key format OK: ${KEY_PREFIX}…${KEY_SUFFIX}"

# ─── Verify key against CometAPI /v1/models ─────────────────────────────────
if [ "${_SETUP_SKIP_VERIFY:-}" = "1" ]; then
  info "Skipping API verification (test mode)"
else

_verify_key_online() {
  _VERIFY_KEY="${COMETAPI_KEY}" node -e "
var https = require('https');
var url = '${_BASE_URL_OPENAI}/models';
var req = https.get(url, { headers: { 'Authorization': 'Bearer ' + process.env._VERIFY_KEY } }, function(res) {
  var body = '';
  res.on('data', function(c) { body += c; });
  res.on('end', function() {
    if (res.statusCode === 200) {
      try {
        var d = JSON.parse(body);
        var count = (d.data && d.data.length) || 0;
        process.stdout.write('OK:' + count);
      } catch(e) { process.stdout.write('OK:0'); }
    } else if (res.statusCode === 401) {
      process.stdout.write('UNAUTHORIZED');
    } else {
      process.stdout.write('ERROR:' + res.statusCode);
    }
  });
});
req.on('error', function(e) { process.stdout.write('NETWORK_ERROR'); });
req.setTimeout(15000, function() { req.destroy(); process.stdout.write('TIMEOUT'); });
" 2>&1
}

_VERIFY_ATTEMPTS=0
_MAX_VERIFY_ATTEMPTS=3

while true; do
  step "Verifying API key against CometAPI…"
  _VERIFY_RESULT="$(_verify_key_online)" || _VERIFY_RESULT="NETWORK_ERROR"

  case "${_VERIFY_RESULT}" in
    OK:*)
      _MODEL_COUNT="${_VERIFY_RESULT#OK:}"
      info "API key verified ✓ (${_MODEL_COUNT} models available)"
      break
      ;;
    UNAUTHORIZED)
      _VERIFY_ATTEMPTS=$((_VERIFY_ATTEMPTS + 1))
      if [ "${_IS_INTERACTIVE}" = "1" ] && [ "${_VERIFY_ATTEMPTS}" -lt "${_MAX_VERIFY_ATTEMPTS}" ]; then
        warn "API key is invalid — CometAPI returned 401 (${_VERIFY_ATTEMPTS}/${_MAX_VERIFY_ATTEMPTS})."
        echo ""
        echo "   👉 Go to ${_KEY_URL} to copy or create a valid key."
        echo ""
        printf "  🔐 Re-enter your CometAPI API key (sk-…): "
        read -r COMETAPI_KEY
        # Re-validate format inline
        case "${COMETAPI_KEY}" in
          sk-???????*) ;;
          *)
            warn "Invalid key format. Must start with 'sk-' and be at least 10 characters."
            echo ""
            echo "   👉 Copy your key from: ${_KEY_URL}"
            echo ""
            continue
            ;;
        esac
      else
        err "API key is invalid — CometAPI returned 401 Unauthorized."
        echo ""
        echo "   Go to ${_KEY_URL} to copy or create a valid key."
        echo ""
        exit 1
      fi
      ;;
    NETWORK_ERROR)
      warn "Could not reach CometAPI to verify key (network error). Proceeding anyway."
      break
      ;;
    TIMEOUT)
      warn "CometAPI verification timed out. Proceeding anyway."
      break
      ;;
    *)
      warn "Unexpected verification response: ${_VERIFY_RESULT}. Proceeding anyway."
      break
      ;;
  esac
done
fi  # end _SETUP_SKIP_VERIFY

# ─── Dry-run banner ─────────────────────────────────────────────────────────
if [ "${DRY_RUN}" = "1" ]; then
  echo ""
  warn "DRY RUN — no files will be modified"
fi

# ─── Core logic via Node.js ─────────────────────────────────────────────────
# All file I/O is handled in a single Node.js invocation for safety:
#   - No sed/awk/grep cross-platform headaches
#   - Proper JSON parsing (not regex on JSON)
#   - Atomic writes with temp files
#   - Works identically on macOS, Linux, WSL, Git Bash
#
# Variables are passed via environment (not heredoc expansion) so the
# heredoc is QUOTED — zero escaping issues with JS regex / template literals.

export _SETUP_ENV_FILE="${ENV_FILE}"
export _SETUP_CONFIG_FILE="${CONFIG_FILE}"
export _SETUP_VAR_NAME="${ENV_VAR_NAME}"
export _SETUP_VAR_VALUE="${COMETAPI_KEY}"
export _SETUP_DRY_RUN="${DRY_RUN}"
export _SETUP_BASE_URL_OPENAI="${_BASE_URL_OPENAI}"
export _SETUP_BASE_URL_ANTHROPIC="${_BASE_URL_ANTHROPIC}"
export _SETUP_BASE_URL_GEMINI="${_BASE_URL_GEMINI}"
export _SETUP_ADD_MODELS="${ADD_MODELS}"

node - <<'NODESCRIPT'
"use strict";
const fs = require("fs");

// ── Inputs from environment ──────────────────────────────────────────────
const ENV_FILE    = process.env._SETUP_ENV_FILE;
const CONFIG_FILE = process.env._SETUP_CONFIG_FILE;
const VAR_NAME    = process.env._SETUP_VAR_NAME;
const VAR_VALUE   = process.env._SETUP_VAR_VALUE;
const DRY_RUN     = process.env._SETUP_DRY_RUN === "1";
const ADD_MODELS  = process.env._SETUP_ADD_MODELS || "";

const BASE_URL_OPENAI     = process.env._SETUP_BASE_URL_OPENAI;
const BASE_URL_ANTHROPIC  = process.env._SETUP_BASE_URL_ANTHROPIC;
const BASE_URL_GEMINI     = process.env._SETUP_BASE_URL_GEMINI;

// ── Step 1: Write key to .env (idempotent) ───────────────────────────────
(function writeEnv() {
  var label = DRY_RUN ? "  🏷️  [DRY RUN] " : "";
  console.log("\n" + label + "📝 Step 1/2 — Writing key to .env");

  var lines = [];
  if (fs.existsSync(ENV_FILE)) {
    lines = fs.readFileSync(ENV_FILE, "utf-8").split("\n");
  }

  // Find and replace, or append
  var pattern = new RegExp("^" + VAR_NAME + "\\s*=");
  var found = false;
  for (var i = 0; i < lines.length; i++) {
    if (pattern.test(lines[i])) {
      lines[i] = VAR_NAME + "=" + VAR_VALUE;
      found = true;
      break;
    }
  }
  if (!found) {
    if (lines.length > 0 && lines[lines.length - 1] === "") {
      lines[lines.length - 1] = VAR_NAME + "=" + VAR_VALUE;
      lines.push("");
    } else {
      lines.push(VAR_NAME + "=" + VAR_VALUE);
    }
  }

  // Remove any duplicate occurrences (idempotency)
  var firstSeen = false;
  lines = lines.filter(function(line) {
    if (pattern.test(line)) {
      if (firstSeen) return false;
      firstSeen = true;
    }
    return true;
  });

  var content = lines.join("\n");
  if (!DRY_RUN) {
    var tmpFile = ENV_FILE + ".tmp." + process.pid;
    fs.writeFileSync(tmpFile, content, { mode: 0o600 });
    fs.renameSync(tmpFile, ENV_FILE);
    try { fs.chmodSync(ENV_FILE, 0o600); } catch(e) { /* Windows: no-op */ }
  }

  console.log("     " + (found ? "↻ Updated" : "✚ Added") + " " + VAR_NAME);
  if (!DRY_RUN) console.log("     🔒 Permissions set to 600");
})();

// ── Step 2: Merge providers into openclaw.json ───────────────────────────
(function mergeConfig() {
  var label = DRY_RUN ? "  🏷️  [DRY RUN] " : "";
  console.log("\n" + label + "📦 Step 2/2 — Merging CometAPI providers");

  var COMETAPI_PROVIDERS = {
    "cometapi-openai": {
      baseUrl: BASE_URL_OPENAI,
      apiKey: "${COMETAPI_KEY}",
      api: "openai-completions",
      models: [{ id: "gpt-5.4", name: "GPT-5.4" }]
    },
    "cometapi-openai-responses": {
      baseUrl: BASE_URL_OPENAI,
      apiKey: "${COMETAPI_KEY}",
      api: "openai-responses",
      models: [{ id: "gpt-5.4-pro", name: "GPT-5.4 Pro" }]
    },
    "cometapi-claude": {
      baseUrl: BASE_URL_ANTHROPIC,
      apiKey: "${COMETAPI_KEY}",
      api: "anthropic-messages",
      models: [{ id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6" }]
    },
    "cometapi-gemini": {
      baseUrl: BASE_URL_GEMINI,
      apiKey: "${COMETAPI_KEY}",
      api: "google-generative-ai",
      models: [{ id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro" }]
    }
  };

  var VALID_PROVIDERS = Object.keys(COMETAPI_PROVIDERS);
  var DEFAULT_PRIMARY = "cometapi-claude/claude-sonnet-4-6";

  // Load existing or start fresh
  var config = {};
  if (fs.existsSync(CONFIG_FILE)) {
    var raw = fs.readFileSync(CONFIG_FILE, "utf-8");
    try {
      config = JSON.parse(raw);
    } catch(e) {
      var backup = CONFIG_FILE + ".bak";
      if (!DRY_RUN) fs.renameSync(CONFIG_FILE, backup);
      console.log("     ⚠️  Invalid JSON — " + (DRY_RUN ? "would back up" : "backed up") + " to " + backup);
      config = {};
    }
  }

  // Migrate: rename cometapi-google → cometapi-gemini if present
  if (!config.models) config.models = {};
  if (!config.models.providers) config.models.providers = {};
  if (config.models.providers["cometapi-google"] && !config.models.providers["cometapi-gemini"]) {
    config.models.providers["cometapi-gemini"] = config.models.providers["cometapi-google"];
    delete config.models.providers["cometapi-google"];
    console.log("     🔄 Migrated: cometapi-google → cometapi-gemini");
  }

  var original = JSON.stringify(config);

  // Build structure
  if (!config.models.mode) config.models.mode = "merge";

  // Merge each CometAPI provider — never touch non-cometapi providers
  var providerNames = Object.keys(COMETAPI_PROVIDERS);
  for (var i = 0; i < providerNames.length; i++) {
    var name = providerNames[i];
    var block = COMETAPI_PROVIDERS[name];
    var existing = config.models.providers[name];
    if (existing) {
      // Preserve user-added models
      var defaultIds = {};
      block.models.forEach(function(m) { defaultIds[m.id] = true; });
      var extras = (existing.models || []).filter(function(m) { return !defaultIds[m.id]; });
      var merged = block.models.concat(extras);
      config.models.providers[name] = Object.assign({}, block, { models: merged });
      console.log("     ↻ " + name);
    } else {
      config.models.providers[name] = block;
      console.log("     ✚ " + name);
    }
  }

  // Process --add-model entries
  if (ADD_MODELS) {
    console.log("");
    console.log("     📋 Adding custom models:");
    var pairs = ADD_MODELS.split(",");
    for (var j = 0; j < pairs.length; j++) {
      var parts = pairs[j].split("/");
      var provName = parts[0];
      var modelId = parts.slice(1).join("/");
      var provider = config.models.providers[provName];
      if (!provider) {
        console.log("     ❌ Unknown provider: " + provName + " (skipped)");
        console.log("        Valid: " + VALID_PROVIDERS.join(", "));
        process.exitCode = 1;
        continue;
      }
      // Check for duplicate
      var already = provider.models.some(function(m) { return m.id === modelId; });
      if (already) {
        console.log("     ℹ️  " + provName + "/" + modelId + " (already exists)");
      } else {
        provider.models.push({ id: modelId, name: modelId });
        console.log("     ✅ " + provName + "/" + modelId);
      }
    }
  }

  // Default model — only if not already set
  if (!config.agents) config.agents = {};
  if (!config.agents.defaults) config.agents.defaults = {};
  if (!config.agents.defaults.model) config.agents.defaults.model = {};
  if (!config.agents.defaults.model.primary) {
    config.agents.defaults.model.primary = DEFAULT_PRIMARY;
    console.log("     🎯 Default model: " + DEFAULT_PRIMARY);
  } else {
    console.log("     🎯 Default model unchanged: " + config.agents.defaults.model.primary);
  }

  // Write only if changed
  var updated = JSON.stringify(config);
  if (updated !== original) {
    if (!DRY_RUN) {
      var tmpCfg = CONFIG_FILE + ".tmp." + process.pid;
      fs.writeFileSync(tmpCfg, JSON.stringify(config, null, 2) + "\n", "utf-8");
      fs.renameSync(tmpCfg, CONFIG_FILE);
    }
    console.log("     💾 " + (DRY_RUN ? "Would write" : "Saved") + " → " + CONFIG_FILE);
  } else {
    console.log("     ℹ️  No changes needed — already up to date");
  }
})();
NODESCRIPT

# Check that the node script succeeded
if [ $? -ne 0 ]; then
  err "Configuration failed. Please check the errors above."
  exit 1
fi

# ─── Step 3: Restart gateway (skip in dry-run) ──────────────────────────────
step "Step 3 — Restarting OpenClaw gateway"

if [ "${DRY_RUN}" = "1" ]; then
  warn "DRY RUN — skipping gateway restart"
else
  if openclaw gateway restart >/dev/null 2>&1; then
    info "Gateway restarted"
  else
    warn "Could not restart gateway automatically."
    detail "Run manually:  openclaw gateway restart"
  fi
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                                                              ║"
echo "  ║   🎉  CometAPI setup complete!                               ║"
echo "  ║                                                              ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  📡 Configured providers:"
echo "     ├─ cometapi-openai            Chat Completions (gpt-5.4 …)"
echo "     ├─ cometapi-openai-responses  Responses API (gpt-5.4-pro …)"
echo "     ├─ cometapi-claude            Anthropic (claude-sonnet-4-6 …)"
echo "     └─ cometapi-gemini            Google AI (gemini-3.1-pro …)"
echo ""
echo "  ⚡ Quick commands:"
echo "     openclaw models status                            # check auth"
echo "     openclaw models list --provider cometapi-claude    # list models"
echo "     openclaw doctor                                    # diagnostics"
echo ""
echo "  🔗 Add more models:  https://api.cometapi.com/models"
echo "  📖 Full docs:        https://docs.cometapi.com/integrations/openclaw"
echo ""
