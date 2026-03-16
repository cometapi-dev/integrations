#Requires -Version 5.1
<#
.SYNOPSIS
    Add CometAPI as a model provider to your local OpenClaw installation.

.DESCRIPTION
    This script configures CometAPI providers in OpenClaw's config files.
    It does NOT install OpenClaw itself.

    What it does:
      1. Verifies OpenClaw + Node.js are installed
      2. Prompts for your CometAPI API key (or reads from -Key / env)
      3. Writes the key to ~/.openclaw/.env (idempotent)
      4. Merges CometAPI provider blocks into ~/.openclaw/openclaw.json
      5. Restarts the OpenClaw gateway

.PARAMETER Key
    CometAPI API key (sk-...). If omitted, reads from $env:COMETAPI_KEY or prompts interactively.

.PARAMETER AddModel
    Add a model to a CometAPI provider. Format: provider/model-id. Can be specified multiple times.
    Example: -AddModel cometapi-openai/gpt-5.2-chat-latest

.PARAMETER DryRun
    Show what would be changed without writing any files.

.EXAMPLE
    .\setup_cometapi.ps1
    # Interactive prompt for API key

.EXAMPLE
    .\setup_cometapi.ps1 -Key sk-xxxxx
    # Non-interactive

.EXAMPLE
    .\setup_cometapi.ps1 -AddModel cometapi-openai/gpt-5.2-chat-latest
    # Add a model to a provider

.EXAMPLE
    .\setup_cometapi.ps1 -AddModel cometapi-claude/claude-sonnet-4-6 -AddModel cometapi-gemini/gemini-3.1-pro

.EXAMPLE
    .\setup_cometapi.ps1 -DryRun
    # Preview changes without writing

.EXAMPLE
    .\setup_cometapi.ps1 -Key sk-testkey1234567890 -SkipVerify
    # Skip API verification (useful in CI/test environments)

.LINK
    https://docs.cometapi.com/integrations/openclaw
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Key,

    [string[]]$AddModel = @(),

    [switch]$DryRun,

    [switch]$SkipVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Constants ───────────────────────────────────────────────────────────────
$ScriptVersion   = "2.0.0"
$OpenClawDir     = Join-Path $HOME ".openclaw"
$EnvFile         = Join-Path $OpenClawDir ".env"
$ConfigFile      = Join-Path $OpenClawDir "openclaw.json"
$EnvVarName      = "COMETAPI_KEY"

$BaseUrlOpenai    = "https://api.cometapi.com/v1"
$BaseUrlAnthropic = "https://api.cometapi.com"
$BaseUrlGemini    = "https://api.cometapi.com/v1beta"

# ─── Output helpers ─────────────────────────────────────────────────────────
function Write-Info   { param([string]$Msg) Write-Host "  ✅ $Msg" -ForegroundColor Green }
function Write-Warn   { param([string]$Msg) Write-Host "  ⚠️  $Msg" -ForegroundColor Yellow }
function Write-Err    { param([string]$Msg) Write-Host "  ❌ $Msg" -ForegroundColor Red }
function Write-Header { param([string]$Msg) Write-Host "`n$Msg" -ForegroundColor Cyan }
function Write-Step   { param([string]$Msg) Write-Host "`n🔧 $Msg" -ForegroundColor Cyan }

# ─── Validate --AddModel format ─────────────────────────────────────────────
foreach ($pair in $AddModel) {
    if ($pair -notmatch '/') {
        Write-Err "Invalid --AddModel format: '$pair' (expected: provider/model-id)"
        exit 1
    }
}

# ─── Pre-flight checks ──────────────────────────────────────────────────────
Write-Header "🔍 Pre-flight checks"

# 1. Node.js
$nodePath = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodePath) {
    Write-Err "Node.js is required but not found."
    Write-Host ""
    Write-Host "   OpenClaw requires Node.js >= 22. Install from:"
    Write-Host "     https://nodejs.org/en/download"
    Write-Host ""
    exit 1
}
$nodeVer = & node --version 2>&1
Write-Info "Node.js $nodeVer"

# 2. OpenClaw CLI
$openclawPath = Get-Command openclaw -ErrorAction SilentlyContinue
if (-not $openclawPath) {
    Write-Err "OpenClaw CLI not found in PATH."
    Write-Host ""
    Write-Host "   Install OpenClaw first, then re-run this script:"
    Write-Host "     npm install -g openclaw@latest"
    Write-Host ""
    Write-Host "   Then run: openclaw onboard --install-daemon"
    Write-Host "   Full guide: https://openclaw.ai"
    exit 1
}
$openclawVer = & openclaw --version 2>&1
Write-Info "OpenClaw $openclawVer"

# 3. ~/.openclaw directory
if (-not (Test-Path $OpenClawDir -PathType Container)) {
    Write-Err "Directory $OpenClawDir does not exist."
    Write-Host ""
    Write-Host "   Run the OpenClaw onboarding first:"
    Write-Host "     openclaw onboard --install-daemon"
    exit 1
}
Write-Info "Config directory: $OpenClawDir"

# ─── Resolve API key ────────────────────────────────────────────────────────
Write-Header "🔑 CometAPI API Key"
$keyUrl = "https://www.cometapi.com/console/token"
Write-Host ""
Write-Host "     Get your key at: $keyUrl" -ForegroundColor DarkGray
Write-Host ""

# Priority: -Key param > $env:COMETAPI_KEY > interactive prompt
$apiKey = if ($Key) { $Key } elseif ($env:COMETAPI_KEY) { $env:COMETAPI_KEY } else { "" }

$isInteractive = -not $apiKey

# ─── Key input + format validation (interactive: up to 3 attempts) ──────────
$keyAttempts = 0
$maxAttempts = 3

while ($true) {
    if ($isInteractive) {
        $apiKey = Read-Host "  🔐 Enter your CometAPI API key (sk-…)"
    }

    $keyAttempts++

    if ($apiKey -match '^sk-.{7,}$') { break }

    if ($isInteractive) {
        if ($keyAttempts -ge $maxAttempts) {
            Write-Err "Invalid key format ($keyAttempts/$maxAttempts). Exiting."
            Write-Host ""
            Write-Host "   Go to $keyUrl to copy or create an API key."
            Write-Host ""
            exit 1
        }
        Write-Warn "Invalid key format ($keyAttempts/$maxAttempts). A CometAPI key starts with 'sk-' and is at least 10 characters."
        Write-Host ""
        Write-Host "   👉 Copy your key from: $keyUrl"
        Write-Host ""
    } else {
        Write-Err "Invalid key format. A CometAPI key starts with 'sk-' and is at least 10 characters."
        Write-Host ""
        Write-Host "   Go to $keyUrl to copy or create an API key."
        Write-Host ""
        exit 1
    }
}

$keyPreview = $apiKey.Substring(0, 6) + "…" + $apiKey.Substring($apiKey.Length - 4)
Write-Info "Key format OK: $keyPreview"

# ─── Verify key against CometAPI /v1/models ─────────────────────────────────
if ($SkipVerify -or $env:_SETUP_SKIP_VERIFY -eq '1') {
    Write-Info "Skipping API verification (test mode)"
} else {
$verifyAttempts = 0

while ($true) {
    Write-Step "Verifying API key against CometAPI…"

    try {
        $headers = @{ "Authorization" = "Bearer $apiKey" }
        $response = Invoke-RestMethod -Uri "$BaseUrlOpenai/models" -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        $modelCount = if ($response.data) { $response.data.Count } else { 0 }
        Write-Info "API key verified ✓ ($modelCount models available)"
        break
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401) {
            $verifyAttempts++
            if ($isInteractive -and $verifyAttempts -lt $maxAttempts) {
                Write-Warn "API key is invalid — CometAPI returned 401 ($verifyAttempts/$maxAttempts)."
                Write-Host ""
                Write-Host "   👉 Go to $keyUrl to copy or create a valid key."
                Write-Host ""
                $apiKey = Read-Host "  🔐 Re-enter your CometAPI API key (sk-…)"
                if ($apiKey -notmatch '^sk-.{7,}$') {
                    Write-Warn "Invalid key format. Must start with 'sk-' and be at least 10 characters."
                    Write-Host ""
                    Write-Host "   👉 Copy your key from: $keyUrl"
                    Write-Host ""
                    continue
                }
            } else {
                Write-Err "API key is invalid — CometAPI returned 401 Unauthorized."
                Write-Host ""
                Write-Host "   Go to $keyUrl to copy or create a valid key."
                Write-Host ""
                exit 1
            }
        } elseif ($_.Exception.Message -match 'Unable to connect|timeout|network') {
            Write-Warn "Could not reach CometAPI to verify key (network error). Proceeding anyway."
            break
        } else {
            Write-Warn "Unexpected verification error: $($_.Exception.Message). Proceeding anyway."
            break
        }
    }
}
} # end SkipVerify

if ($DryRun) {
    Write-Host ""
    Write-Warn "DRY RUN — no files will be modified"
}

# ─── Step 1: Write key to .env ───────────────────────────────────────────────
Write-Step "Step 1/2 — Writing key to .env"

$envLine = "$EnvVarName=$apiKey"
$lines = @()
$found = $false

if (Test-Path $EnvFile) {
    $lines = @(Get-Content $EnvFile -Raw -ErrorAction SilentlyContinue) -split "`n"
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match "^$EnvVarName\s*=") {
            if (-not $found) {
                $newLines += $envLine
                $found = $true
            }
            # Skip duplicates
        } else {
            $newLines += $line
        }
    }
    $lines = $newLines
}

if (-not $found) {
    $lines += $envLine
    Write-Host "     ✚ Added $EnvVarName"
} else {
    Write-Host "     ↻ Updated $EnvVarName"
}

if (-not $DryRun) {
    $content = ($lines -join "`n").TrimEnd("`n") + "`n"
    $tmpFile = "$EnvFile.tmp.$PID"
    [System.IO.File]::WriteAllText($tmpFile, $content)
    Move-Item -Path $tmpFile -Destination $EnvFile -Force
    Write-Host "     🔒 .env configured"
}

# ─── Step 2: Merge providers into openclaw.json ─────────────────────────────
Write-Step "Step 2/2 — Merging CometAPI providers"

# Prepare add-model data as comma-separated string for Node.js
$addModelsStr = ($AddModel -join ",")

# Use Node.js for JSON merging — same logic as the shell script
$nodeScript = @"
"use strict";
const fs = require("fs");

const CONFIG_FILE = $($ConfigFile | ConvertTo-Json);
const DRY_RUN     = $($DryRun.IsPresent.ToString().ToLower());
const ADD_MODELS  = "$addModelsStr";

const COMETAPI_PROVIDERS = {
  "cometapi-openai": {
    baseUrl: "$BaseUrlOpenai",
    apiKey: "\${COMETAPI_KEY}",
    api: "openai-completions",
    models: [{ id: "gpt-5.4", name: "GPT-5.4" }]
  },
  "cometapi-openai-responses": {
    baseUrl: "$BaseUrlOpenai",
    apiKey: "\${COMETAPI_KEY}",
    api: "openai-responses",
    models: [{ id: "gpt-5.4-pro", name: "GPT-5.4 Pro" }]
  },
  "cometapi-claude": {
    baseUrl: "$BaseUrlAnthropic",
    apiKey: "\${COMETAPI_KEY}",
    api: "anthropic-messages",
    models: [{ id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6" }]
  },
  "cometapi-gemini": {
    baseUrl: "$BaseUrlGemini",
    apiKey: "\${COMETAPI_KEY}",
    api: "google-generative-ai",
    models: [{ id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro" }]
  }
};

const VALID_PROVIDERS = Object.keys(COMETAPI_PROVIDERS);
const DEFAULT_PRIMARY = "cometapi-claude/claude-sonnet-4-6";

let config = {};
if (fs.existsSync(CONFIG_FILE)) {
  try {
    config = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf-8"));
  } catch(e) {
    const backup = CONFIG_FILE + ".bak";
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

const original = JSON.stringify(config);

if (!config.models.mode) config.models.mode = "merge";

for (const [name, block] of Object.entries(COMETAPI_PROVIDERS)) {
  const existing = config.models.providers[name];
  if (existing) {
    const defaultIds = new Set(block.models.map(m => m.id));
    const extras = (existing.models || []).filter(m => !defaultIds.has(m.id));
    config.models.providers[name] = { ...block, models: [...block.models, ...extras] };
    console.log("     ↻ " + name);
  } else {
    config.models.providers[name] = block;
    console.log("     ✚ " + name);
  }
}

// Process --AddModel entries
if (ADD_MODELS) {
  console.log("");
  console.log("     📋 Adding custom models:");
  const pairs = ADD_MODELS.split(",");
  for (const pair of pairs) {
    const idx = pair.indexOf("/");
    const provName = pair.substring(0, idx);
    const modelId = pair.substring(idx + 1);
    const provider = config.models.providers[provName];
    if (!provider) {
      console.log("     ❌ Unknown provider: " + provName + " (skipped)");
      console.log("        Valid: " + VALID_PROVIDERS.join(", "));
      process.exitCode = 1;
      continue;
    }
    if (provider.models.some(m => m.id === modelId)) {
      console.log("     ℹ️  " + provName + "/" + modelId + " (already exists)");
    } else {
      provider.models.push({ id: modelId, name: modelId });
      console.log("     ✅ " + provName + "/" + modelId);
    }
  }
}

if (!config.agents) config.agents = {};
if (!config.agents.defaults) config.agents.defaults = {};
if (!config.agents.defaults.model) config.agents.defaults.model = {};
if (!config.agents.defaults.model.primary) {
  config.agents.defaults.model.primary = DEFAULT_PRIMARY;
  console.log("     🎯 Default model: " + DEFAULT_PRIMARY);
} else {
  console.log("     🎯 Default model unchanged: " + config.agents.defaults.model.primary);
}

if (JSON.stringify(config) !== original) {
  if (!DRY_RUN) {
    const tmp = CONFIG_FILE + ".tmp." + process.pid;
    fs.writeFileSync(tmp, JSON.stringify(config, null, 2) + "\n", "utf-8");
    fs.renameSync(tmp, CONFIG_FILE);
  }
  console.log("     💾 " + (DRY_RUN ? "Would write" : "Saved") + " → " + CONFIG_FILE);
} else {
  console.log("     ℹ️  No changes needed — already up to date");
}
"@

$nodeScript | & node -

if ($LASTEXITCODE -ne 0) {
    Write-Err "Configuration failed."
    exit 1
}

# ─── Step 3: Restart gateway ────────────────────────────────────────────────
Write-Step "Step 3 — Restarting OpenClaw gateway"

if ($DryRun) {
    Write-Warn "DRY RUN — skipping gateway restart"
} else {
    try {
        & openclaw gateway restart 2>&1 | Out-Null
        Write-Info "Gateway restarted"
    } catch {
        Write-Warn "Could not restart gateway automatically."
        Write-Host "   Run manually: openclaw gateway restart"
    }
}

# ─── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗"
Write-Host "  ║                                                              ║"
Write-Host "  ║   🎉  CometAPI setup complete!                               ║"
Write-Host "  ║                                                              ║"
Write-Host "  ╚══════════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "  📡 Configured providers:"
Write-Host "     ├─ cometapi-openai            Chat Completions (gpt-5.4 …)"
Write-Host "     ├─ cometapi-openai-responses  Responses API (gpt-5.4-pro …)"
Write-Host "     ├─ cometapi-claude            Anthropic (claude-sonnet-4-6 …)"
Write-Host "     └─ cometapi-gemini            Google AI (gemini-3.1-pro …)"
Write-Host ""
Write-Host "  ⚡ Quick commands:"
Write-Host "     openclaw models status                            # check auth"
Write-Host "     openclaw models list --provider cometapi-claude    # list models"
Write-Host "     openclaw doctor                                    # diagnostics"
Write-Host ""
Write-Host "  🔗 Add more models:  https://api.cometapi.com/models"
Write-Host "  📖 Full docs:        https://docs.cometapi.com/integrations/openclaw"
Write-Host ""
