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

function Test-ObjectProperty([object]$Object, [string]$Name) {
    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Set-ObjectProperty([object]$Object, [string]$Name, [object]$Value) {
    if (Test-ObjectProperty $Object $Name) {
        $Object.PSObject.Properties[$Name].Value = $Value
    } else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function New-CodexNotifierHookGroup([string]$ScriptName) {
    return [ordered]@{
        hooks = @(
            [ordered]@{
                type = "command"
                command = Get-PortableHookCommand $ScriptName
                timeout = 10
            }
        )
    }
}

function Test-CodexNotifierCommand([object]$Hook, [string]$ScriptName) {
    if ($null -eq $Hook -or -not (Test-ObjectProperty $Hook "command")) {
        return $false
    }

    $command = [string]$Hook.command
    return (-not [string]::IsNullOrWhiteSpace($command) -and $command -like "*$ScriptName*")
}

function Merge-CodexNotifierHook([object]$HooksRoot, [string]$EventName, [string]$ScriptName) {
    $existingGroups = @()
    if (Test-ObjectProperty $HooksRoot $EventName) {
        $existingGroups = @($HooksRoot.PSObject.Properties[$EventName].Value)
    }

    $mergedGroups = New-Object System.Collections.Generic.List[object]

    foreach ($group in $existingGroups) {
        if ($null -eq $group) {
            continue
        }

        if (-not (Test-ObjectProperty $group "hooks")) {
            # Preserve unexpected group shapes instead of deleting user config.
            $mergedGroups.Add($group)
            continue
        }

        $filteredHooks = @()
        foreach ($hook in @($group.hooks)) {
            if (-not (Test-CodexNotifierCommand $hook $ScriptName)) {
                $filteredHooks += $hook
            }
        }

        if ($filteredHooks.Count -gt 0) {
            Set-ObjectProperty $group "hooks" @($filteredHooks)
            $mergedGroups.Add($group)
        }
    }

    $mergedGroups.Add((New-CodexNotifierHookGroup $ScriptName))
    Set-ObjectProperty $HooksRoot $EventName @($mergedGroups.ToArray())
}

function Read-CodexHooksConfig([string]$HooksJsonPath) {
    if (-not (Test-Path -LiteralPath $HooksJsonPath)) {
        return [pscustomobject]@{
            hooks = [pscustomobject]@{}
        }
    }

    $text = Get-Content -LiteralPath $HooksJsonPath -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{
            hooks = [pscustomobject]@{}
        }
    }

    try {
        $config = $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Existing hooks.json is not valid JSON: $HooksJsonPath. A backup was created; fix or remove the file and rerun install.ps1. $($_.Exception.Message)"
    }

    if ($null -eq $config) {
        $config = [pscustomobject]@{}
    }

    if (-not (Test-ObjectProperty $config "hooks") -or $null -eq $config.hooks -or $config.hooks -isnot [pscustomobject]) {
        Set-ObjectProperty $config "hooks" ([pscustomobject]@{})
    }

    return $config
}

function Merge-CodexHooksConfig([string]$HooksJsonPath) {
    $config = Read-CodexHooksConfig $HooksJsonPath
    Merge-CodexNotifierHook $config.hooks "Stop" "codex_done.ps1"
    Merge-CodexNotifierHook $config.hooks "PermissionRequest" "codex_permission_notify.ps1"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $HooksJsonPath -Encoding UTF8
    Write-Info "Merged notifier hooks into $HooksJsonPath"
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

Merge-CodexHooksConfig $hooksJsonPath

if (-not $SkipConfigEdit) {
    Backup-IfExists $configPath
    Ensure-FeatureHooksEnabled $configPath
}

Write-Host ""
Write-Info "Done."
Write-Host "Next steps:"
Write-Host "  1. Restart Codex / reload the VS Code Codex extension."
Write-Host "  2. If Codex says hooks need review, run /hooks and approve the two local commands."
Write-Host "  3. Use scripts\\test-notification.ps1 to quick-test the installed notifier."
