param(
    [ValidateSet("done", "permission", "both")]
    [string]$Kind = "both",
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" })
)

$ErrorActionPreference = "Stop"

$hookDir = Join-Path $CodexHome "hooks"
$doneScript = Join-Path $hookDir "codex_done.ps1"
$permissionScript = Join-Path $hookDir "codex_permission_notify.ps1"

function Invoke-HookScript([string]$ScriptPath, [hashtable]$Payload) {
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Hook script not found: $ScriptPath"
    }

    $json = $Payload | ConvertTo-Json -Compress
    Write-Host "Invoking $ScriptPath"
    $json | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
}

$cwd = (Get-Location).Path
$sessionId = "test-session-12345678"

if ($Kind -in @("done", "both")) {
    Invoke-HookScript $doneScript @{
        hook_event_name = "Stop"
        cwd = $cwd
        session_id = $sessionId
        last_assistant_message = "Smoke test completed."
    }
}

if ($Kind -in @("permission", "both")) {
    Invoke-HookScript $permissionScript @{
        hook_event_name = "PermissionRequest"
        cwd = $cwd
        session_id = $sessionId
        tool_name = "shell"
        tool_input = @{
            command = "echo test"
        }
    }
}

