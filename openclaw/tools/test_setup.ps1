#!/usr/bin/env pwsh
# =============================================================================
# test_setup.ps1 — End-to-end tests for setup.ps1
# Run with:  pwsh openclaw/tools/test_setup.ps1
# =============================================================================
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir   = Split-Path $MyInvocation.MyCommand.Path
$SetupScript = Join-Path $ScriptDir "..\setup.ps1"
$TestDir     = Join-Path ([System.IO.Path]::GetTempPath()) "ps1_test_$(Get-Random)"
$Pass = 0; $Fail = 0; $Total = 0

# ─── Cleanup ─────────────────────────────────────────────────────────────────
function Cleanup { if (Test-Path $TestDir) { Remove-Item -Recurse -Force $TestDir } }
Register-EngineEvent PowerShell.Exiting -Action { Cleanup } | Out-Null

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Ok   { param([string]$Desc) $script:Pass++; $script:Total++; Write-Host "  ✅ PASS: $Desc" -ForegroundColor Green }
function Fail { param([string]$Desc) $script:Fail++; $script:Total++; Write-Host "  ❌ FAIL: $Desc" -ForegroundColor Red }

function Assert-Eq {
    param([string]$Desc, $Expected, $Actual)
    if ($Expected -eq $Actual) { Ok $Desc }
    else { Fail "$Desc (expected='$Expected', got='$Actual')" }
}

function Assert-Contains {
    param([string]$Desc, [string]$Haystack, [string]$Needle)
    if ($Haystack -match [regex]::Escape($Needle)) { Ok $Desc }
    else { Fail "$Desc — missing '$Needle'" }
}

function Assert-NotContains {
    param([string]$Desc, [string]$Haystack, [string]$Needle)
    if ($Haystack -notmatch [regex]::Escape($Needle)) { Ok $Desc }
    else { Fail "$Desc — unexpectedly present '$Needle'" }
}

function Get-JsonField {
    param([string]$File, [string]$KeyPath)
    $d = Get-Content $File -Raw | ConvertFrom-Json
    $keys = $KeyPath -split '\.'
    $v = $d
    foreach ($k in $keys) { $v = $v.$k }
    return [string]$v
}

function Assert-JsonField {
    param([string]$Desc, [string]$File, [string]$KeyPath, [string]$Expected)
    try {
        $actual = Get-JsonField $File $KeyPath
        Assert-Eq $Desc $Expected $actual
    } catch {
        Fail "$Desc (exception reading JSON: $_)"
    }
}

# ─── Mock environment setup ──────────────────────────────────────────────────
$FakeHome = $null
$FakeBin  = $null

function Setup-Env {
    $script:FakeHome = Join-Path $TestDir "fakehome_$(Get-Random)"
    $script:FakeBin  = Join-Path $TestDir "fakebin_$(Get-Random)"
    $ocDir = Join-Path $FakeHome ".openclaw"
    New-Item -ItemType Directory -Force $ocDir | Out-Null
    New-Item -ItemType Directory -Force $FakeBin | Out-Null

    # Mock openclaw binary — real sh executable (macOS/Linux compatible with pwsh)
    $mockPath = Join-Path $FakeBin "openclaw"
    # Use single-quoted PS strings so $1, $2, $* are NOT expanded by PowerShell
    $mockLines = @(
        '#!/bin/sh',
        'case "$1" in',
        "  --version) echo 'openclaw 2026.3.8-mock' ;;",
        '  gateway)   echo "gateway $2 ok (mock)" ;;',
        '  *)         echo "openclaw mock: $*" ;;',
        'esac'
    )
    [System.IO.File]::WriteAllText($mockPath, ($mockLines -join "`n") + "`n")
    & /bin/chmod +x $mockPath
}

function Invoke-Setup {
    param([string]$Key, [string[]]$ExtraArgs = @())
    $allArgs = @("-Key", $Key, "-SkipVerify") + $ExtraArgs
    $env:HOME = $FakeHome
    $origPath = $env:PATH
    $env:PATH  = "$FakeBin$([System.IO.Path]::PathSeparator)$origPath"
    try {
        $output = pwsh -NonInteractive -NoProfile -File $SetupScript @allArgs 2>&1 | Out-String
    } finally {
        $env:HOME = $HOME
        $env:PATH = $origPath
    }
    return $output
}

$ConfigFile = $null

function Get-ConfigFile { return Join-Path $FakeHome ".openclaw" "openclaw.json" }
function Get-EnvFile    { return Join-Path $FakeHome ".openclaw" ".env" }

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Test Suite: setup.ps1 v2.0  (pwsh $($PSVersionTable.PSVersion))" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ── Test 1: Fresh install ─────────────────────────────────────────────────────
Write-Host "`n── Test 1: Fresh install (empty ~/.openclaw) ──"
Setup-Env
$out = Invoke-Setup -Key "sk-testfresh1234567"

$envContent = Get-Content (Get-EnvFile) -Raw
Assert-Contains "1a: .env contains COMETAPI_KEY"     $envContent "COMETAPI_KEY=sk-testfresh1234567"
Assert-JsonField "1b: cometapi-openai api"            (Get-ConfigFile) "models.providers.cometapi-openai.api"             "openai-completions"
Assert-JsonField "1c: cometapi-claude api"            (Get-ConfigFile) "models.providers.cometapi-claude.api"             "anthropic-messages"
Assert-JsonField "1d: cometapi-gemini api"            (Get-ConfigFile) "models.providers.cometapi-gemini.api"             "google-generative-ai"
Assert-JsonField "1e: cometapi-responses api"          (Get-ConfigFile) "models.providers.cometapi-responses.api"             "openai-responses"
Assert-JsonField "1f: default model"                  (Get-ConfigFile) "agents.defaults.model.primary"                    "cometapi-claude/claude-sonnet-4-6"
Assert-JsonField "1g: models.mode is merge"           (Get-ConfigFile) "models.mode"                                      "merge"
Assert-JsonField "1h: baseUrl openai"                 (Get-ConfigFile) "models.providers.cometapi-openai.baseUrl"         "https://api.cometapi.com/v1"
Assert-JsonField "1i: apiKey uses env var ref"        (Get-ConfigFile) "models.providers.cometapi-openai.apiKey"          '${COMETAPI_KEY}'

# ── Test 2: Idempotency ───────────────────────────────────────────────────────
Write-Host "`n── Test 2: Idempotency (run same key again) ──"
Invoke-Setup -Key "sk-testfresh1234567" | Out-Null

$keyCount = @(Get-Content (Get-EnvFile) | Where-Object { $_ -match '^COMETAPI_KEY=' }).Count
Assert-Eq "2a: .env has exactly 1 COMETAPI_KEY line" 1 $keyCount

$cfg = Get-Content (Get-ConfigFile) -Raw | ConvertFrom-Json
$provCount = @($cfg.models.providers.PSObject.Properties | Where-Object { $_.Name -like 'cometapi-*' }).Count
Assert-Eq "2b: still exactly 4 cometapi providers" 4 $provCount

# ── Test 3: Key update ────────────────────────────────────────────────────────
Write-Host "`n── Test 3: Key update (new key replaces old) ──"
Invoke-Setup -Key "sk-newkey999888777" | Out-Null

$envContent = Get-Content (Get-EnvFile) -Raw
Assert-Contains "3a: .env has new key"  $envContent "COMETAPI_KEY=sk-newkey999888777"
$keyCount = @(Get-Content (Get-EnvFile) | Where-Object { $_ -match '^COMETAPI_KEY=' }).Count
Assert-Eq "3b: still exactly 1 COMETAPI_KEY line" 1 $keyCount

# ── Test 4: Non-destructive (existing providers preserved) ────────────────────
Write-Host "`n── Test 4: Non-destructive (existing providers preserved) ──"
Setup-Env
$existing = @{
    models = @{
        mode = "merge"
        providers = @{
            "my-openai" = @{ api = "openai-completions"; baseUrl = "https://api.openai.com/v1"; apiKey = '${OPENAI_KEY}' }
        }
    }
    agents = @{ defaults = @{ model = @{ primary = "my-openai/gpt-4o" } } }
}
$existing | ConvertTo-Json -Depth 10 | Set-Content (Get-ConfigFile)
Set-Content (Get-EnvFile) "OPENAI_KEY=sk-existing"

Invoke-Setup -Key "sk-test4444444444444" | Out-Null

$cfg = Get-Content (Get-ConfigFile) -Raw | ConvertFrom-Json
Assert-Eq   "4a: existing my-openai preserved" "openai-completions" $cfg.models.providers.'my-openai'.api
Assert-Eq   "4b: existing default model preserved" "my-openai/gpt-4o" $cfg.agents.defaults.model.primary
$provCount = @($cfg.models.providers.PSObject.Properties).Count
Assert-Eq   "4c: total 5 providers (1 existing + 4 cometapi)" 5 $provCount
$envContent = Get-Content (Get-EnvFile) -Raw
Assert-Contains "4d: OPENAI_KEY preserved in .env" $envContent "OPENAI_KEY=sk-existing"
Assert-Contains "4e: COMETAPI_KEY added to .env"   $envContent "COMETAPI_KEY=sk-test4444444444444"

# ── Test 5: --DryRun ─────────────────────────────────────────────────────────
Write-Host "`n── Test 5: --DryRun mode ──"
Setup-Env
$out = Invoke-Setup -Key "sk-testdryrun123456" -ExtraArgs @("-DryRun")

Assert-Contains "5a: DRY RUN in output" $out "DRY RUN"
Assert-Eq       "5b: .env not created"  $false (Test-Path (Get-EnvFile))
Assert-Eq       "5c: json not created"  $false (Test-Path (Get-ConfigFile))

# ── Test 6: Invalid key rejection ─────────────────────────────────────────────
Write-Host "`n── Test 6: Invalid key rejection ──"
Setup-Env
$proc = Start-Process pwsh -ArgumentList @("-NonInteractive", "-NoProfile", "-File", $SetupScript, "-Key", "short", "-SkipVerify") -Wait -PassThru -NoNewWindow
Assert-Eq "6a: short key exits non-zero" $true ($proc.ExitCode -ne 0)

$proc2 = Start-Process pwsh -ArgumentList @("-NonInteractive", "-NoProfile", "-File", $SetupScript, "-Key", "notstartwithsk1234", "-SkipVerify") -Wait -PassThru -NoNewWindow
Assert-Eq "6b: key without sk- prefix exits non-zero" $true ($proc2.ExitCode -ne 0)

# ── Test 7: --AddModel ────────────────────────────────────────────────────────
Write-Host "`n── Test 7: --AddModel flag ──"
Setup-Env
$out = Invoke-Setup -Key "sk-testaddmodel12345" -ExtraArgs @("-AddModel", "cometapi-openai/gpt-5-test")

Assert-Contains "7a: output confirms model added" $out "gpt-5-test"
$cfg = Get-Content (Get-ConfigFile) -Raw | ConvertFrom-Json
$modelIds = $cfg.models.providers.'cometapi-openai'.models | ForEach-Object { $_.id }
Assert-Eq "7b: gpt-5-test in cometapi-openai models" $true ($modelIds -contains "gpt-5-test")

# ── Test 8: --AddModel deduplication ─────────────────────────────────────────
Write-Host "`n── Test 8: --AddModel deduplication ──"
Invoke-Setup -Key "sk-testaddmodel12345" -ExtraArgs @("-AddModel", "cometapi-openai/gpt-5-test") | Out-Null
$cfg = Get-Content (Get-ConfigFile) -Raw | ConvertFrom-Json
$dupeCount = @($cfg.models.providers.'cometapi-openai'.models | Where-Object { $_.id -eq "gpt-5-test" }).Count
Assert-Eq "8a: no duplicate gpt-5-test" 1 $dupeCount

# ── Test 9: --AddModel invalid format ────────────────────────────────────────
Write-Host "`n── Test 9: --AddModel invalid format ──"
Setup-Env
$proc = Start-Process pwsh -ArgumentList @("-NonInteractive", "-NoProfile", "-File", $SetupScript, "-Key", "sk-testaddmodel12345", "-AddModel", "noslash", "-SkipVerify") -Wait -PassThru -NoNewWindow
Assert-Eq "9a: invalid AddModel format exits non-zero" $true ($proc.ExitCode -ne 0)

# ── Test 10: --AddModel unknown provider ─────────────────────────────────────
Write-Host "`n── Test 10: --AddModel unknown provider ──"
Setup-Env
$out = Invoke-Setup -Key "sk-testaddmodel12345" -ExtraArgs @("-AddModel", "unknown-provider/some-model")
Assert-Contains "10a: warns about unknown provider" $out "unknown"

# ── Test 11: Idempotency stress (5 runs) ─────────────────────────────────────
Write-Host "`n── Test 11: Idempotency stress (5 consecutive runs) ──"
Setup-Env
1..5 | ForEach-Object { Invoke-Setup -Key "sk-stresstest12345678" | Out-Null }
$keyCount = @(Get-Content (Get-EnvFile) | Where-Object { $_ -match '^COMETAPI_KEY=' }).Count
Assert-Eq "11a: .env has exactly 1 key after 5 runs" 1 $keyCount
$cfg = Get-Content (Get-ConfigFile) -Raw | ConvertFrom-Json
$provCount = @($cfg.models.providers.PSObject.Properties | Where-Object { $_.Name -like 'cometapi-*' }).Count
Assert-Eq "11b: exactly 4 cometapi providers after 5 runs" 4 $provCount

# ── Test 12: Missing openclaw CLI ─────────────────────────────────────────────
Write-Host "`n── Test 12: Missing openclaw CLI ──"
$emptyBin = Join-Path $TestDir "emptybin"
New-Item -ItemType Directory -Force $emptyBin | Out-Null
$freshHome = Join-Path $TestDir "freshHome2"
New-Item -ItemType Directory -Force (Join-Path $freshHome ".openclaw") | Out-Null

# Add a node wrapper so pre-flight for node passes, but NO openclaw
$realNode = (Get-Command node -ErrorAction Stop).Source
$nodeWrapper = Join-Path $emptyBin "node"
[System.IO.File]::WriteAllText($nodeWrapper, "#!/bin/sh`nexec '$realNode' `"`$@`"`n")
& /bin/chmod +x $nodeWrapper

$savedHome12 = $env:HOME
$savedPath12 = $env:PATH
$env:HOME = $freshHome
$env:PATH = $emptyBin   # only emptyBin — openclaw not present anywhere
$proc = Start-Process pwsh -ArgumentList @("-NonInteractive", "-NoProfile", "-File", $SetupScript, "-Key", "sk-test12121212121212", "-SkipVerify") -Wait -PassThru -NoNewWindow
$env:HOME = $savedHome12
$env:PATH = $savedPath12
Assert-Eq "12a: exits non-zero when openclaw missing" $true ($proc.ExitCode -ne 0)

# ── Test 13: Legacy provider rename migration ────────────────────────────────
Write-Host "`n── Test 13: Legacy provider rename migration ──"
Setup-Env
@{
    models = @{
        mode = "merge"
        providers = @{
            "cometapi-openai-responses" = @{
                baseUrl = "https://api.cometapi.com/v1"
                apiKey = '${COMETAPI_KEY}'
                api = "openai-responses"
                models = @(
                    @{ id = "gpt-5.4-pro"; name = "GPT-5.4 Pro" },
                    @{ id = "o1-mini"; name = "o1-mini (user added)" }
                )
            }
        }
    }
} | ConvertTo-Json -Depth 20 | Set-Content (Get-ConfigFile)

$out13 = Invoke-Setup -Key "sk-legacyresp12345678"
Assert-Contains "13a: migration message shown" $out13 "cometapi-openai-responses"
$cfg13 = Get-Content (Get-ConfigFile) -Raw | ConvertFrom-Json
Assert-Eq "13b: old provider removed" $false ($cfg13.models.providers.PSObject.Properties.Name -contains 'cometapi-openai-responses')
Assert-Eq "13c: new provider exists" "openai-responses" $cfg13.models.providers.'cometapi-responses'.api
$ids13 = @($cfg13.models.providers.'cometapi-responses'.models | ForEach-Object { $_.id })
Assert-Eq "13d: user-added o1-mini preserved" $true ($ids13 -contains 'o1-mini')

# ── Test 14: Real E2E — strip & restore real openclaw.json ───────────────────
Write-Host "`n── Test 14: Real E2E (real openclaw.json on this machine) ──"
$realConfigPath = Join-Path $HOME ".openclaw" "openclaw.json"
$backupPath     = Join-Path $HOME ".openclaw" "openclaw.json.ps1test_backup"

if (Test-Path $realConfigPath) {
    Copy-Item $realConfigPath $backupPath -Force
    # Strip cometapi providers
    $realCfg = Get-Content $realConfigPath -Raw | ConvertFrom-Json
    $toRemove = @('cometapi-openai','cometapi-responses','cometapi-claude','cometapi-gemini')
    foreach ($p in $toRemove) {
        if ($realCfg.models.providers.PSObject.Properties[$p]) {
            $realCfg.models.providers.PSObject.Properties.Remove($p)
        }
    }
    $realCfg | ConvertTo-Json -Depth 20 | Set-Content $realConfigPath
    $before = @($realCfg.models.providers.PSObject.Properties | Where-Object { $_.Name -like 'cometapi-*' }).Count
    Assert-Eq "14a: cometapi providers stripped from real config" 0 $before

    # Run real script with real key (no -SkipVerify)
    $realKey = $env:COMETAPI_KEY
    if (-not $realKey) { $realKey = @(Get-Content (Join-Path $HOME ".openclaw" ".env") | Where-Object { $_ -match '^COMETAPI_KEY=' })[0] -replace 'COMETAPI_KEY=','' }

    if ($realKey) {
        $realOut = pwsh -NonInteractive -NoProfile -File $SetupScript -Key $realKey 2>&1 | Out-String
        Assert-Contains "14b: API key verified" $realOut "verified"
        Assert-Contains "14c: all 4 providers added" $realOut "cometapi-gemini"

        $finalCfg = Get-Content $realConfigPath -Raw | ConvertFrom-Json
        $afterCount = @($finalCfg.models.providers.PSObject.Properties | Where-Object { $_.Name -like 'cometapi-*' }).Count
        Assert-Eq "14d: 4 cometapi providers in real config after setup" 4 $afterCount
    } else {
        Write-Host "  ⚠️  Skipping 14b-14d: no real API key found" -ForegroundColor Yellow
    }

    # Restore backup
    Copy-Item $backupPath $realConfigPath -Force
    Remove-Item $backupPath -Force
    Write-Host "  ↩  Real config restored" -ForegroundColor DarkGray
} else {
    Write-Host "  ⚠️  Skipping Test 14: no real openclaw.json found" -ForegroundColor Yellow
}

# ── Test 15: -AddModel without key in NonInteractive mode ───────────────────
Write-Host "`n── Test 15: -AddModel without key in NonInteractive mode ──"
$noKeyHome14 = Join-Path $TestDir "noKeyAddModelHome14"
New-Item -ItemType Directory -Force (Join-Path $noKeyHome14 ".openclaw") | Out-Null
$helper14 = Join-Path $TestDir "missing_key_addmodel_14.ps1"
$helper14Content = @"
`$env:COMETAPI_KEY = `$null
& ([scriptblock]::Create((Get-Content '$SetupScript' -Raw))) -AddModel 'cometapi-openai/gpt-5.2-chat-latest'
"@
$helper14Content | Set-Content $helper14
$savedHome14 = $env:HOME
$env:HOME = $noKeyHome14
$output14 = pwsh -NonInteractive -NoProfile -File $helper14 2>&1 | Out-String
$env:HOME = $savedHome14
$exit14 = $LASTEXITCODE
Assert-Eq "15a: exits non-zero when -AddModel has no key" $true ($exit14 -ne 0)
Assert-Contains "15b: shows missing key message" $output14 "No API key provided"
Assert-Contains "15c: shows -Key + -AddModel example" $output14 "-Key 'sk-xxxxx' -AddModel 'cometapi-openai/gpt-5.2-chat-latest'"

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
$summaryColor = if ($Fail -eq 0) { "Green" } else { "Red" }
Write-Host "  Results: $Pass passed, $Fail failed, $Total total" -ForegroundColor $summaryColor
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
if ($Fail -eq 0) {
    Write-Host "`n  All tests passed! ✨" -ForegroundColor Green
} else {
    Write-Host "`n  Some tests FAILED. See above." -ForegroundColor Red
    exit 1
}

Cleanup
