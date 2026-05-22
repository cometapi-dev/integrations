#!/bin/sh
# One-click CometAPI provider setup for Codex.
# Platform: macOS, Linux, WSL, Git Bash.

set -eu

SCRIPT_VERSION="1.0.0"
DEFAULT_MODEL="gpt-5.5"
BASE_URL="https://api.cometapi.com/v1"
KEY_URL="https://www.cometapi.com/console/token"

ARG_KEY=""
MODEL="$DEFAULT_MODEL"
MODEL_SET=0
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
DRY_RUN=0
SKIP_VERIFY=0
FORCE_AUTH_JSON=0

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  GREEN="$(printf '\033[0;32m')"
  YELLOW="$(printf '\033[1;33m')"
  RED="$(printf '\033[0;31m')"
  CYAN="$(printf '\033[0;36m')"
  RESET="$(printf '\033[0m')"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; RESET=""
fi

info() { printf "  %sOK%s  %s\n" "$GREEN" "$RESET" "$*"; }
warn() { printf "  %sWARN%s  %s\n" "$YELLOW" "$RESET" "$*"; }
err() { printf "  %sERR%s  %s\n" "$RED" "$RESET" "$*" >&2; }
step() { printf "\n%s%s%s\n" "$CYAN" "$*" "$RESET"; }

show_help() {
  cat <<'EOF'
Usage: curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh | sh -s -- [OPTIONS]

Configure Codex to use CometAPI without replacing an existing ChatGPT login.

Options:
  --key KEY             CometAPI API key. Defaults to COMETAPI_KEY env var or saved key file.
  --model MODEL         Codex model ID to set. Default: gpt-5.5
  --codex-home PATH     Codex state directory. Default: CODEX_HOME or ~/.codex
  --dry-run             Show changes without writing files
  --skip-verify         Skip CometAPI and Codex runtime checks
  --force-auth-json     Legacy mode: write ~/.codex/auth.json with API key auth
  --help, -h            Show this help message
  --version             Show script version

Examples:
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh)"
  curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh | sh -s -- --key sk-xxxxx
  curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh | sh -s -- --key sk-xxxxx --model your-model-id
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --key)
      [ $# -ge 2 ] || { err "--key requires a value"; exit 1; }
      ARG_KEY="$2"; shift 2 ;;
    --key=*)
      ARG_KEY="${1#*=}"; shift ;;
    --model)
      [ $# -ge 2 ] || { err "--model requires a value"; exit 1; }
      MODEL="$2"; MODEL_SET=1; shift 2 ;;
    --model=*)
      MODEL="${1#*=}"; MODEL_SET=1; shift ;;
    --codex-home)
      [ $# -ge 2 ] || { err "--codex-home requires a value"; exit 1; }
      CODEX_HOME_DIR="$2"; shift 2 ;;
    --codex-home=*)
      CODEX_HOME_DIR="${1#*=}"; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --skip-verify)
      SKIP_VERIFY=1; shift ;;
    --force-auth-json)
      FORCE_AUTH_JSON=1; shift ;;
    --help|-h)
      show_help; exit 0 ;;
    --version)
      printf 'setup.sh v%s\n' "$SCRIPT_VERSION"; exit 0 ;;
    -*)
      err "Unknown option: $1"; exit 1 ;;
    *)
      ARG_KEY="$1"; shift ;;
  esac
done

CONFIG_FILE="${CODEX_HOME_DIR}/config.toml"
AUTH_FILE="${CODEX_HOME_DIR}/auth.json"
KEY_FILE="${CODEX_HOME_DIR}/cometapi_api_key"
ROLLBACK_FILE="${TMPDIR:-/tmp}/cometapi-codex-rollback.$$"
WRITES_FILE="${TMPDIR:-/tmp}/cometapi-codex-writes.$$"
: > "$ROLLBACK_FILE"
: > "$WRITES_FILE"

cleanup() {
  rm -f "$ROLLBACK_FILE" "$WRITES_FILE"
}
trap cleanup EXIT

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_saved_key() {
  [ -f "$KEY_FILE" ] || return 1
  _saved_key="$(sed -n '1p' "$KEY_FILE" | tr -d '\r\n')"
  [ -n "$_saved_key" ] || return 1
  printf '%s' "$_saved_key"
}

resolve_key() {
  _env_key="${COMETAPI_KEY:-}"
  _saved_key=""
  if [ -z "$ARG_KEY" ] && [ -z "$_env_key" ]; then
    _saved_key="$(read_saved_key || true)"
  fi

  COMETAPI_KEY_VALUE="${ARG_KEY:-${_env_key:-${_saved_key:-}}}"
  _key_source="prompt"
  if [ -n "$ARG_KEY" ]; then
    _key_source="flag"
  elif [ -n "$_env_key" ]; then
    _key_source="env"
  elif [ -n "$_saved_key" ]; then
    _key_source="key_file"
  fi

  if [ "$_key_source" = "key_file" ]; then
    info "Using saved CometAPI key from $KEY_FILE"
  fi

  if [ -z "$COMETAPI_KEY_VALUE" ]; then
    if [ ! -t 0 ]; then
      err "No API key provided and stdin is not a terminal."
      printf '\nThis happens with piped installs such as curl ... | sh.\n' >&2
      printf 'Use one of these forms:\n' >&2
      printf '  sh -c "$(curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh)"\n' >&2
      printf '  curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh | sh -s -- --key sk-xxxxx\n' >&2
      printf '  COMETAPI_KEY=sk-xxxxx sh -c "$(curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh)"\n' >&2
      printf '\nGet a key at: %s\n' "$KEY_URL" >&2
      exit 1
    fi
  fi

  _attempts=0
  _max_attempts=3
  while :; do
    if [ -z "$COMETAPI_KEY_VALUE" ]; then
      printf "CometAPI API key (sk-...): "
      read -r COMETAPI_KEY_VALUE
    fi
    _attempts=$((_attempts + 1))

    case "$COMETAPI_KEY_VALUE" in
      sk-???????*) break ;;
      *)
        if [ -t 0 ] && [ "$_key_source" = "prompt" ]; then
          if [ "$_attempts" -ge "$_max_attempts" ]; then
            err "Invalid key format ($_attempts/$_max_attempts). Exiting."
            printf 'Get a key at: %s\n' "$KEY_URL" >&2
            exit 1
          fi
          warn "Invalid key format ($_attempts/$_max_attempts). A CometAPI key starts with sk- and is at least 10 characters."
          printf 'Get a key at: %s\n\n' "$KEY_URL"
          COMETAPI_KEY_VALUE=""
        else
          err "Invalid key format. A CometAPI key starts with sk- and is at least 10 characters."
          printf 'Get a key at: %s\n' "$KEY_URL" >&2
          exit 1
        fi ;;
    esac
  done
}

resolve_model() {
  if [ "$MODEL_SET" = "0" ] && [ -t 0 ]; then
    printf "Codex model [%s]: " "$DEFAULT_MODEL"
    read -r _model_input
    if [ -n "$_model_input" ]; then
      MODEL="$_model_input"
    fi
  fi
}

auth_json_is_chatgpt() {
  [ -f "$AUTH_FILE" ] || return 1
  grep -Eq '"auth_mode"[[:space:]]*:[[:space:]]*"chatgpt"' "$AUTH_FILE"
}

resolve_auth_mode() {
  if [ "$FORCE_AUTH_JSON" = "1" ]; then
    warn "Legacy auth mode enabled: auth.json will be managed after backup"
    return 0
  fi

  if auth_json_is_chatgpt; then
    if [ -t 0 ]; then
      warn "Existing ChatGPT auth detected in $AUTH_FILE"
      printf "Replace auth.json with CometAPI API-key auth? [y/N]: "
      read -r _auth_choice
      case "$_auth_choice" in
        y|Y|yes|YES)
          FORCE_AUTH_JSON=1
          warn "auth.json will be backed up and replaced with CometAPI API-key auth" ;;
        *)
          info "Keeping existing ChatGPT auth.json; using provider auth command" ;;
      esac
    else
      info "Existing ChatGPT auth.json detected; keeping it because --force-auth-json was not set"
    fi
  else
    info "Default auth mode: existing auth.json will not be touched"
  fi
}

backup_before_write() {
  _file="$1"
  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi
  if [ -f "$_file" ]; then
    _backup="${_file}.bak.$(date +%Y%m%d%H%M%S).$$"
    cp "$_file" "$_backup" || return 1
    printf '%s|%s\n' "$_file" "$_backup" >> "$ROLLBACK_FILE"
  else
    printf '%s|\n' "$_file" >> "$ROLLBACK_FILE"
  fi
}

write_if_changed() {
  _file="$1"
  _content="$2"
  _mode="${3:-600}"

  if [ -f "$_file" ] && [ "$(cat "$_file")" = "$(printf '%s' "$_content" | sed '$ s/$//')" ]; then
    info "No change: $_file"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    warn "[dry-run] Would write: $_file"
    printf '%s\n' "$_file" >> "$WRITES_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$_file")" || rollback_and_exit "Failed to create directory for $_file"
  backup_before_write "$_file" || rollback_and_exit "Failed to back up $_file"
  _tmp="${_file}.tmp.$$"
  umask 077
  if ! printf '%s' "$_content" > "$_tmp"; then
    rm -f "$_tmp"
    rollback_and_exit "Failed to write temporary file for $_file"
  fi
  if ! mv "$_tmp" "$_file"; then
    rm -f "$_tmp"
    rollback_and_exit "Failed to replace $_file"
  fi
  chmod "$_mode" "$_file" 2>/dev/null || true
  printf '%s\n' "$_file" >> "$WRITES_FILE"
  info "Wrote: $_file"
}

rollback_and_exit() {
  _reason="$1"
  err "$_reason"
  if [ "$DRY_RUN" = "1" ]; then
    exit 1
  fi
  if [ -s "$ROLLBACK_FILE" ]; then
    warn "Rolling back files changed by this run"
    while IFS='|' read -r _file _backup; do
      if [ -n "$_backup" ] && [ -f "$_backup" ]; then
        cp "$_backup" "$_file"
      else
        rm -f "$_file"
      fi
    done < "$ROLLBACK_FILE"
  fi
  exit 1
}

verify_key_online() {
  if [ "$SKIP_VERIFY" = "1" ]; then
    info "Skipping CometAPI key verification"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not found; skipping CometAPI key verification"
    return 0
  fi

  _body="${TMPDIR:-/tmp}/cometapi-codex-models.$$"
  _status="$(curl -sS -o "$_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${COMETAPI_KEY_VALUE}" \
    "${BASE_URL}/models" 2>/dev/null || printf '000')"
  rm -f "$_body"

  case "$_status" in
    200) info "CometAPI key verified" ;;
    401|403) err "CometAPI rejected the API key (HTTP $_status)"; exit 1 ;;
    *) warn "Could not verify key against CometAPI (HTTP $_status). Continuing." ;;
  esac
}

render_config() {
  _model_escaped="$(toml_escape "$MODEL")"
  _key_file_escaped="$(toml_escape "$KEY_FILE")"
  _input="/dev/null"
  [ -f "$CONFIG_FILE" ] && _input="$CONFIG_FILE"

  awk \
    -v model="$_model_escaped" \
    -v key_file="$_key_file_escaped" \
    -v force_auth="$FORCE_AUTH_JSON" '
BEGIN { in_root = 1; }
function print_missing() {
  if (!seen_provider) emit("model_provider = \"cometapi\"");
  if (!seen_model) emit("model = \"" model "\"");
  printed_missing = 1;
}
function emit(line) {
  if (line ~ /^[[:space:]]*$/) {
    blank_count++;
    return;
  }
  while (blank_count > 0) {
    print "";
    blank_count--;
  }
  print line;
}
function is_header(line) { return line ~ /^[[:space:]]*\[/; }
function is_our_header(line) {
  return line ~ /^[[:space:]]*\[model_providers[.]cometapi(\]|[.](auth)\])/;
}
{
  if (skip_ours) {
    if (is_header($0)) {
      skip_ours = 0;
    } else {
      next;
    }
  }

  if (is_our_header($0)) {
    if (in_root && !printed_missing) print_missing();
    in_root = 0;
    skip_ours = 1;
    next;
  }

  if (is_header($0) && in_root) {
    if (!printed_missing) print_missing();
    in_root = 0;
  }

  if (in_root && $0 ~ /^[[:space:]]*model_provider[[:space:]]*=/) {
    emit("model_provider = \"cometapi\"");
    seen_provider = 1;
    next;
  }
  if (in_root && $0 ~ /^[[:space:]]*model[[:space:]]*=/) {
    emit("model = \"" model "\"");
    seen_model = 1;
    next;
  }
  emit($0);
}
END {
  if (NR == 0) in_root = 1;
  if (in_root && !printed_missing) print_missing();
  blank_count = 0;
  print "";
  print "[model_providers.cometapi]";
  print "name = \"CometAPI\"";
  print "base_url = \"https://api.cometapi.com/v1\"";
  print "wire_api = \"responses\"";
  if (force_auth == "1") {
    print "requires_openai_auth = true";
  } else {
    print "";
    print "[model_providers.cometapi.auth]";
    print "command = \"cat\"";
    print "args = [\"" key_file "\"]";
  }
}
' "$_input"
}

render_auth_json() {
  _key_json="$(json_escape "$COMETAPI_KEY_VALUE")"
  printf '{\n  "auth_mode": "apikey",\n  "OPENAI_API_KEY": "%s"\n}\n' "$_key_json"
}

verify_codex_runtime() {
  if [ "$SKIP_VERIFY" = "1" ]; then
    info "Skipping Codex runtime verification"
    return 0
  fi
  if ! command -v codex >/dev/null 2>&1; then
    warn "Codex CLI not found in PATH. Open Codex App or install Codex CLI to test the setup."
    return 0
  fi

  _workdir="$(mktemp -d "${TMPDIR:-/tmp}/cometapi-codex-check.XXXXXX")"
  _prompt="Reply exactly with: COMETAPI_CODEX_OK"
  set +e
  _out="$(CODEX_HOME="$CODEX_HOME_DIR" codex exec --ephemeral --skip-git-repo-check --sandbox read-only --color never -C "$_workdir" "$_prompt" 2>&1)"
  _code=$?
  set -e
  rm -rf "$_workdir"

  if [ "$_code" -ne 0 ]; then
    printf '%s\n' "$_out" >&2
    rollback_and_exit "Codex runtime verification failed"
  fi
  case "$_out" in
    *COMETAPI_CODEX_OK*) info "Codex runtime verified" ;;
    *)
      printf '%s\n' "$_out" >&2
      rollback_and_exit "Codex runtime verification did not return the expected marker" ;;
  esac
}

step "Pre-flight checks"
resolve_key
resolve_model
resolve_auth_mode
info "Codex home: $CODEX_HOME_DIR"
info "Model: $MODEL"

step "Verify CometAPI key"
verify_key_online

step "Prepare Codex configuration"
CONFIG_CONTENT="$(render_config)"
write_if_changed "$CONFIG_FILE" "${CONFIG_CONTENT}
" 600

if [ "$FORCE_AUTH_JSON" = "1" ]; then
  write_if_changed "$AUTH_FILE" "$(render_auth_json)" 600
else
  write_if_changed "$KEY_FILE" "${COMETAPI_KEY_VALUE}
" 600
fi

step "Verify Codex runtime"
verify_codex_runtime

printf '\nCometAPI Codex setup complete.\n'
printf 'Config: %s\n' "$CONFIG_FILE"
if [ "$FORCE_AUTH_JSON" = "1" ]; then
  printf 'Auth:   %s\n' "$AUTH_FILE"
else
  printf 'Key:    %s\n' "$KEY_FILE"
fi
