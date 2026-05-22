#Requires -Version 5.1
<#
.SYNOPSIS
    Configure Codex to use CometAPI.

.DESCRIPTION
    This script configures the CometAPI model provider in Codex without
    replacing an existing ChatGPT login. Use -ForceAuthJson only when you want
    the legacy auth.json API-key mode.

.EXAMPLE
    powershell -c "irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1' | iex"
    # Interactive prompt for API key and model.

.EXAMPLE
    powershell -c "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1'))) -Key '<COMETAPI_KEY>'"
    # Non-interactive setup.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Key,

    [string]$Model,

    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }),

    [switch]$DryRun,

    [switch]$SkipVerify,

    [switch]$ForceAuthJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptVersion = "1.0.0"
$DefaultModel = "gpt-5.5"
$ModelWasProvided = $PSBoundParameters.ContainsKey("Model")
if (-not $Model) { $Model = $DefaultModel }
$BaseUrl = "https://api.cometapi.com/v1"
$KeyUrl = "https://www.cometapi.com/console/token"
$ConfigFile = Join-Path $CodexHome "config.toml"
$AuthFile = Join-Path $CodexHome "auth.json"
$KeyFile = Join-Path $CodexHome "cometapi_api_key"
$Rollback = New-Object System.Collections.Generic.List[object]

function Write-Info { param([string]$Message) Write-Host "  OK    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "  WARN  $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "  ERR   $Message" -ForegroundColor Red }
function Write-Step { param([string]$Message) Write-Host "`n$Message" -ForegroundColor Cyan }

function Escape-TomlString {
    param([string]$Value)
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Get-SavedCometApiKey {
    if (-not (Test-Path $KeyFile -PathType Leaf)) { return $null }
    $saved = ([System.IO.File]::ReadAllText($KeyFile)).Trim()
    if ($saved) { return $saved }
    return $null
}

function Resolve-ApiKey {
    $envKey = $env:COMETAPI_KEY
    $savedKey = if ($Key -or $envKey) { $null } else { Get-SavedCometApiKey }
    $apiKey = if ($Key) { $Key } elseif ($envKey) { $envKey } elseif ($savedKey) { $savedKey } else { "" }

    $script:ApiKeySource = if ($Key) { "param" } elseif ($envKey) { "env" } elseif ($savedKey) { "key_file" } else { "prompt" }
    if ($script:ApiKeySource -eq "key_file") {
        Write-Info "Using saved CometAPI key from $KeyFile"
    }

    $isInteractive = -not $apiKey
    $attempts = 0
    $maxAttempts = 3

    while ($true) {
        if ($isInteractive) {
            try {
                $apiKey = Read-Host "CometAPI API key (sk-...)"
            } catch {
                Write-Err "No API key provided and PowerShell is non-interactive."
                Write-Host ""
                Write-Host "Use one of these forms:"
                Write-Host "  powershell -c `"irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1' | iex`""
                Write-Host "  powershell -c `"& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1'))) -Key 'sk-xxxxx'`""
                Write-Host "Get a key at: $KeyUrl"
                exit 1
            }
        }
        $attempts++

        if ($apiKey -match '^sk-.{7,}$') { break }

        if ($isInteractive) {
            if ($attempts -ge $maxAttempts) {
                Write-Err "Invalid key format ($attempts/$maxAttempts). Exiting."
                Write-Host "Get a key at: $KeyUrl"
                exit 1
            }
            Write-Warn "Invalid key format ($attempts/$maxAttempts). A CometAPI key starts with sk- and is at least 10 characters."
            Write-Host "Get a key at: $KeyUrl"
            $apiKey = ""
        } else {
            Write-Err "Invalid key format. A CometAPI key starts with sk- and is at least 10 characters."
            Write-Host "Get a key at: $KeyUrl"
            exit 1
        }
    }
    return $apiKey
}

function Resolve-Model {
    if (-not $ModelWasProvided -and $script:ApiKeySource -eq "prompt") {
        try {
            $inputModel = Read-Host "Codex model [$DefaultModel]"
            if ($inputModel) { $script:Model = $inputModel }
        } catch {
            $script:Model = $DefaultModel
        }
    }
    if (-not $script:Model) { $script:Model = $DefaultModel }
}

function Test-AuthJsonIsChatGpt {
    if (-not (Test-Path $AuthFile -PathType Leaf)) { return $false }
    $content = [System.IO.File]::ReadAllText($AuthFile)
    return $content -match '"auth_mode"\s*:\s*"chatgpt"'
}

function Resolve-AuthMode {
    if ($ForceAuthJson) {
        Write-Warn "Legacy auth mode enabled: auth.json will be managed after backup"
        return
    }

    if (Test-AuthJsonIsChatGpt) {
        if ($script:ApiKeySource -eq "prompt") {
            Write-Warn "Existing ChatGPT auth detected in $AuthFile"
            try {
                $choice = Read-Host "Replace auth.json with CometAPI API-key auth? [y/N]"
            } catch {
                $choice = ""
            }
            if ($choice -match '^(y|yes)$') {
                $script:ForceAuthJson = $true
                Write-Warn "auth.json will be backed up and replaced with CometAPI API-key auth"
            } else {
                Write-Info "Keeping existing ChatGPT auth.json; using provider auth command"
            }
        } else {
            Write-Info "Existing ChatGPT auth.json detected; keeping it because -ForceAuthJson was not set"
        }
    } else {
        Write-Info "Default auth mode: existing auth.json will not be touched"
    }
}

function Add-Backup {
    param([string]$Path)
    if ($DryRun) { return }
    if (Test-Path $Path -PathType Leaf) {
        $backup = "$Path.bak.$(Get-Date -Format yyyyMMddHHmmss).$PID"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        $Rollback.Add([pscustomobject]@{ Path = $Path; Backup = $backup }) | Out-Null
    } else {
        $Rollback.Add([pscustomobject]@{ Path = $Path; Backup = $null }) | Out-Null
    }
}

function Restore-AndExit {
    param([string]$Reason)
    Write-Err $Reason
    if (-not $DryRun -and $Rollback.Count -gt 0) {
        Write-Warn "Rolling back files changed by this run"
        foreach ($entry in $Rollback) {
            if ($entry.Backup -and (Test-Path $entry.Backup -PathType Leaf)) {
                Copy-Item -LiteralPath $entry.Backup -Destination $entry.Path -Force
            } else {
                Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
            }
        }
    }
    exit 1
}

function Write-ChangedFile {
    param(
        [string]$Path,
        [string]$Content,
        [switch]$Secret
    )

    if ((Test-Path $Path -PathType Leaf) -and ([System.IO.File]::ReadAllText($Path) -eq $Content)) {
        Write-Info "No change: $Path"
        return
    }

    if ($DryRun) {
        Write-Warn "[dry-run] Would write: $Path"
        return
    }

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Add-Backup -Path $Path
    $tmp = "$Path.tmp.$PID"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $Content, $encoding)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    if ($Secret -and (Get-Command chmod -ErrorAction SilentlyContinue)) {
        & chmod 600 $Path 2>$null
    }
    Write-Info "Wrote: $Path"
}

function Get-DesiredConfig {
    param([string]$Current, [string]$ApiKeyFile)

    $lines = if ($Current) { $Current -split "`r?`n" } else { @() }
    $out = New-Object System.Collections.Generic.List[string]
    $inRoot = $true
    $seenProvider = $false
    $seenModel = $false
    $printedMissing = $false
    $skipOurs = $false

    function Add-MissingRoot {
        if (-not $seenProvider) { $out.Add('model_provider = "cometapi"') | Out-Null }
        if (-not $seenModel) { $out.Add(('model = "{0}"' -f (Escape-TomlString $Model))) | Out-Null }
        Set-Variable -Name printedMissing -Value $true -Scope 1
    }

    foreach ($line in $lines) {
        $isHeader = $line -match '^\s*\['
        if ($skipOurs) {
            if ($isHeader) {
                $skipOurs = $false
            } else {
                continue
            }
        }

        if ($line -match '^\s*\[model_providers[.]cometapi(\]|[.](auth)\])') {
            if ($inRoot -and -not $printedMissing) { Add-MissingRoot }
            $inRoot = $false
            $skipOurs = $true
            continue
        }

        if ($isHeader -and $inRoot) {
            if (-not $printedMissing) { Add-MissingRoot }
            $inRoot = $false
        }

        if ($inRoot -and $line -match '^\s*model_provider\s*=') {
            $out.Add('model_provider = "cometapi"') | Out-Null
            $seenProvider = $true
            continue
        }
        if ($inRoot -and $line -match '^\s*model\s*=') {
            $out.Add(('model = "{0}"' -f (Escape-TomlString $Model))) | Out-Null
            $seenModel = $true
            continue
        }
        $out.Add($line) | Out-Null
    }

    if ($inRoot -and -not $printedMissing) { Add-MissingRoot }

    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq "") {
        $out.RemoveAt($out.Count - 1)
    }

    $out.Add("") | Out-Null
    $out.Add("[model_providers.cometapi]") | Out-Null
    $out.Add('name = "CometAPI"') | Out-Null
    $out.Add('base_url = "https://api.cometapi.com/v1"') | Out-Null
    $out.Add('wire_api = "responses"') | Out-Null
    if ($ForceAuthJson) {
        $out.Add('requires_openai_auth = true') | Out-Null
    } else {
        $isWindowsHost = (-not $PSVersionTable.ContainsKey("Platform")) -or $PSVersionTable.Platform -eq "Win32NT"
        $out.Add("") | Out-Null
        $out.Add("[model_providers.cometapi.auth]") | Out-Null
        if ($isWindowsHost) {
            $literalPath = $ApiKeyFile.Replace("'", "''")
            $command = "(Get-Content -Raw -LiteralPath '$literalPath').Trim()"
            $out.Add('command = "powershell.exe"') | Out-Null
            $out.Add(('args = ["-NoProfile", "-Command", "{0}"]' -f (Escape-TomlString $command))) | Out-Null
        } else {
            $out.Add('command = "cat"') | Out-Null
            $out.Add(('args = ["{0}"]' -f (Escape-TomlString $ApiKeyFile))) | Out-Null
        }
    }

    return (($out -join "`n") + "`n")
}

function Get-AuthJson {
    param([string]$ApiKey)
    $obj = [ordered]@{
        auth_mode = "apikey"
        OPENAI_API_KEY = $ApiKey
    }
    return (($obj | ConvertTo-Json -Depth 3) + "`n")
}

function Test-CometApiKey {
    param([string]$ApiKey)
    if ($SkipVerify) {
        Write-Info "Skipping CometAPI key verification"
        return
    }
    try {
        $headers = @{ Authorization = "Bearer $ApiKey" }
        Invoke-RestMethod -Uri "$BaseUrl/models" -Headers $headers -TimeoutSec 15 -ErrorAction Stop | Out-Null
        Write-Info "CometAPI key verified"
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Err "CometAPI rejected the API key (HTTP $statusCode)"
            exit 1
        }
        Write-Warn "Could not verify key against CometAPI. Continuing. $($_.Exception.Message)"
    }
}

function Test-RunnableCommandPath {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.LinkType -eq "SymbolicLink" -and $item.Target) {
            foreach ($target in @($item.Target)) {
                $resolved = if ([System.IO.Path]::IsPathRooted($target)) {
                    $target
                } else {
                    Join-Path (Split-Path -Parent $Path) $target
                }
                if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                    return $false
                }
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Test-CodexRuntime {
    if ($SkipVerify) {
        Write-Info "Skipping Codex runtime verification"
        return
    }
    $codex = $null
    foreach ($candidate in (Get-Command codex -All -ErrorAction SilentlyContinue)) {
        $path = if ($candidate.Source) { $candidate.Source } else { $candidate.Definition }
        if (-not $path) { continue }
        if (-not (Test-RunnableCommandPath -Path $path)) { continue }
        & $path --version *> $null
        if ($LASTEXITCODE -eq 0) {
            $codex = $path
            break
        }
    }
    if (-not $codex) {
        Write-Warn "Codex CLI not found in PATH. Open Codex App or install Codex CLI to test the setup."
        return
    }

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cometapi-codex-check-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    $oldCodexHome = $env:CODEX_HOME
    $env:CODEX_HOME = $CodexHome
    try {
        $output = & $codex exec --ephemeral --skip-git-repo-check --sandbox read-only --color never -C $workDir "Reply exactly with: COMETAPI_CODEX_OK" 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $env:CODEX_HOME = $oldCodexHome
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    }

    $text = ($output | Out-String)
    if ($exitCode -ne 0) {
        Write-Host $text
        Restore-AndExit "Codex runtime verification failed"
    }
    if ($text -notmatch 'COMETAPI_CODEX_OK') {
        Write-Host $text
        Restore-AndExit "Codex runtime verification did not return the expected marker"
    }
    Write-Info "Codex runtime verified"
}

Write-Step "Pre-flight checks"
$ApiKey = Resolve-ApiKey
Resolve-Model
Resolve-AuthMode
Write-Info "Codex home: $CodexHome"
Write-Info "Model: $Model"

Write-Step "Verify CometAPI key"
Test-CometApiKey -ApiKey $ApiKey

Write-Step "Prepare Codex configuration"
try {
    $currentConfig = if (Test-Path $ConfigFile -PathType Leaf) { [System.IO.File]::ReadAllText($ConfigFile) } else { "" }
    $desiredConfig = Get-DesiredConfig -Current $currentConfig -ApiKeyFile $KeyFile
    Write-ChangedFile -Path $ConfigFile -Content $desiredConfig -Secret

    if ($ForceAuthJson) {
        Write-ChangedFile -Path $AuthFile -Content (Get-AuthJson -ApiKey $ApiKey) -Secret
    } else {
        Write-ChangedFile -Path $KeyFile -Content ($ApiKey + "`n") -Secret
    }

    Write-Step "Verify Codex runtime"
    Test-CodexRuntime
} catch {
    Restore-AndExit "Setup failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "CometAPI Codex setup complete."
Write-Host "Config: $ConfigFile"
if ($ForceAuthJson) {
    Write-Host "Auth:   $AuthFile"
} else {
    Write-Host "Key:    $KeyFile"
}
