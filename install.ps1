param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }),
    [switch]$SkipConfigEdit
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) {
    Write-Host "[codex-task-notifier] $Message"
}

function Backup-IfExists([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = "$Path.bak_$stamp"
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Info "Backed up $Path -> $backupPath"
    }
}

function Ensure-FeatureHooksEnabled([string]$ConfigPath) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Set-Content -LiteralPath $ConfigPath -Value "[features]`nhooks = true`n" -Encoding UTF8
        Write-Info "Created config.toml with [features].hooks = true"
        return
    }

    $text = Get-Content -LiteralPath $ConfigPath -Raw
    $lines = @($text -split "`r?`n", -1)
    $featuresIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[features\]\s*$') {
            $featuresIndex = $i
            break
        }
    }

    if ($featuresIndex -lt 0) {
        $newText = $text.TrimEnd() + "`r`n`r`n[features]`r`nhooks = true`r`n"
        Set-Content -LiteralPath $ConfigPath -Value $newText -Encoding UTF8
        Write-Info "Added [features].hooks = true"
        return
    }

    $nextTableIndex = $lines.Count
    for ($i = $featuresIndex + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') {
            $nextTableIndex = $i
            break
        }
    }

    $hooksLineIndex = -1
    for ($i = $featuresIndex + 1; $i -lt $nextTableIndex; $i++) {
        if ($lines[$i] -match '^\s*hooks\s*=') {
            $hooksLineIndex = $i
            break
        }
    }

    if ($hooksLineIndex -ge 0) {
        $lines[$hooksLineIndex] = "hooks = true"
        Write-Info "Updated existing [features].hooks = true"
    } else {
        $before = $lines[0..$featuresIndex]
        $after = if ($featuresIndex + 1 -le $lines.Count - 1) { $lines[($featuresIndex + 1)..($lines.Count - 1)] } else { @() }
        $lines = @($before + "hooks = true" + $after)
        Write-Info "Inserted [features].hooks = true"
    }

    Set-Content -LiteralPath $ConfigPath -Value ($lines -join "`r`n") -Encoding UTF8
}

function Get-PortableHookCommand([string]$ScriptName) {
    # Keep hooks.json portable and avoid writing absolute paths such as
    # user-profile-specific paths into Codex config. At hook runtime, resolve Codex home
    # from CODEX_HOME when present, otherwise from USERPROFILE\.codex.
    $template = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ''.codex'' }; & (Join-Path $codexHome ''hooks\__SCRIPT_NAME__'')"'
    return $template.Replace("__SCRIPT_NAME__", $ScriptName)
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceHooksDir = Join-Path $repoRoot "hooks"
$targetHooksDir = Join-Path $CodexHome "hooks"
$hooksJsonPath = Join-Path $CodexHome "hooks.json"
$configPath = Join-Path $CodexHome "config.toml"

foreach ($required in @(
    (Join-Path $sourceHooksDir "codex_done.ps1"),
    (Join-Path $sourceHooksDir "codex_permission_notify.ps1"),
    (Join-Path $sourceHooksDir "codex_notify_worker.ps1")
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file not found: $required"
    }
}

New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
New-Item -ItemType Directory -Path $targetHooksDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceHooksDir "codex_done.ps1") -Destination (Join-Path $targetHooksDir "codex_done.ps1") -Force
Copy-Item -LiteralPath (Join-Path $sourceHooksDir "codex_permission_notify.ps1") -Destination (Join-Path $targetHooksDir "codex_permission_notify.ps1") -Force
Copy-Item -LiteralPath (Join-Path $sourceHooksDir "codex_notify_worker.ps1") -Destination (Join-Path $targetHooksDir "codex_notify_worker.ps1") -Force
Write-Info "Installed hook scripts to $targetHooksDir"

Backup-IfExists $hooksJsonPath

if ($CodexHome -ne (Join-Path $env:USERPROFILE ".codex") -and -not $env:CODEX_HOME) {
    Write-Info "Custom CodexHome was provided. Set CODEX_HOME to the same path before running Codex so portable hook commands can resolve it."
}

$hooksConfig = [ordered]@{
    hooks = [ordered]@{
        Stop = @(
            [ordered]@{
                hooks = @(
                    [ordered]@{
                        type = "command"
                        command = Get-PortableHookCommand "codex_done.ps1"
                        timeout = 10
                    }
                )
            }
        )
        PermissionRequest = @(
            [ordered]@{
                hooks = @(
                    [ordered]@{
                        type = "command"
                        command = Get-PortableHookCommand "codex_permission_notify.ps1"
                        timeout = 10
                    }
                )
            }
        )
    }
}

$hooksConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hooksJsonPath -Encoding UTF8
Write-Info "Wrote $hooksJsonPath"

if (-not $SkipConfigEdit) {
    Backup-IfExists $configPath
    Ensure-FeatureHooksEnabled $configPath
}

Write-Host ""
Write-Info "Done."
Write-Host "Next steps:"
Write-Host "  1. Restart Codex / reload the VS Code Codex extension."
Write-Host "  2. If Codex says hooks need review, run /hooks and approve the two local commands."
Write-Host "  3. Use scripts\\test-notification.ps1 to smoke-test the installed notifier."
