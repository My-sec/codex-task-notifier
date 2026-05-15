# Codex Task Notifier

Windows PowerShell hooks for Codex that show a desktop popup and play a sound when:

- a Codex turn/task finishes (`Stop` hook);
- Codex asks for manual permission (`PermissionRequest` hook).

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

## What is included

```text
hooks/
  codex_done.ps1                 # Stop hook entry point: task completed
  codex_permission_notify.ps1    # PermissionRequest hook entry point
  codex_notify_worker.ps1        # Shared popup + sound worker
scripts/
  test-notification.ps1          # Local quick test
examples/
  hooks.json                     # Manual hooks.json example
  config.toml.snippet            # Minimal config.toml feature snippet
install.ps1                      # Installer for ~/.codex
```

## Requirements

- Windows desktop environment.
- PowerShell 5.1+.
- Codex CLI / VS Code Codex with hooks support.
- Codex hooks feature enabled:

```toml
[features]
hooks = true
```

Do **not** use the deprecated setting:

```toml
[features]
codex_hooks = true
```

## Quick install

Clone the repository:

```powershell
git clone https://github.com/My-sec/codex-task-notifier.git
cd codex-task-notifier
```

Install into your Codex home directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

By default, the installer uses:

```text
%USERPROFILE%\.codex
```

If you use a custom Codex home:

```powershell
$env:CODEX_HOME = "<your-codex-home>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -CodexHome $env:CODEX_HOME
```

The generated hook commands do not contain your Windows user name. They resolve the Codex home at runtime from `CODEX_HOME`, or from `%USERPROFILE%\.codex` when `CODEX_HOME` is not set.

The generated hook commands use `powershell.exe -EncodedCommand`. This avoids failures on Windows when an outer PowerShell shell expands `$env:CODEX_HOME` or `$codexHome` before the command reaches the inner PowerShell process, which can otherwise make the hook fail with `exit code 1`.

The installer will:

1. copy the three hook scripts to `<CodexHome>\hooks`;
2. create or merge `<CodexHome>\hooks.json`;
3. ensure `<CodexHome>\config.toml` contains `[features].hooks = true`;
4. back up existing `hooks.json` and `config.toml` before modifying them.

When `hooks.json` already exists, the installer preserves existing hook events and commands. It only removes older `codex_done.ps1` / `codex_permission_notify.ps1` entries and then adds the current notifier hooks.

## Required Codex approval step

After installation, restart Codex or reload the VS Code Codex extension.

Codex may show:

```text
1 hook needs review before it can run. Open /hooks to review it.
```

Run this command inside Codex:

```text
/hooks
```

Review and approve the two local PowerShell hook commands.

This is required by Codex's hook security model.

## Manual installation

1. Copy the scripts:

```text
hooks\codex_done.ps1
hooks\codex_permission_notify.ps1
hooks\codex_notify_worker.ps1
```

to:

```text
%USERPROFILE%\.codex\hooks
```

2. Create or update:

```text
%USERPROFILE%\.codex\hooks.json
```

Use [examples/hooks.json](examples/hooks.json). The example resolves the hook directory at runtime from `CODEX_HOME` or `%USERPROFILE%`, so it does not need a hard-coded absolute user path.

3. Ensure:

```text
%USERPROFILE%\.codex\config.toml
```

contains:

```toml
[features]
hooks = true
```

4. Restart Codex and approve hooks with `/hooks`.

## Local quick test

After installing, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-notification.ps1 -Kind both
```

You should see:

- a "task completed" popup;
- a "permission required" popup;
- a short notification sound.

Runtime logs are written next to the installed scripts:

```text
%USERPROFILE%\.codex\hooks\codex_done.log
```

## Permission reminder caveat

The `PermissionRequest` popup only appears when Codex actually asks for manual permission.

If your Codex config uses:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

then permission prompts are usually not triggered. In that configuration, the task-complete popup can still work, but the manual-permission popup may rarely or never appear.

To test permission reminders, use a configuration that can request approval, for example:

```toml
approval_policy = "on-request"
```

## Security notes

- Inspect the PowerShell scripts before approving them in `/hooks`.
- The scripts only use local Windows APIs for popup and sound notifications.
- The scripts do not send network requests.
- The installer backs up existing Codex config files before modifying them.

## Troubleshooting

### No popup appears

Check:

1. `hooks.json` exists under your Codex home.
2. `[features].hooks = true` is present in `config.toml`.
3. You restarted Codex after installation.
4. You approved the hooks via `/hooks`.
5. Run the local quick test script manually.

### Completion popup works, permission popup does not

This is usually expected when Codex is configured not to ask for approval. See [Permission reminder caveat](#permission-reminder-caveat).

### Change the sound

Use a WAV file. The worker checks custom sounds before built-in Windows sounds:

1. `CODEX_NOTIFY_SOUND`, if the environment variable points to an existing `.wav` file.
2. `%USERPROFILE%\.codex\hooks\codex_notify.wav`, if that file exists.
3. Built-in Windows notification WAV files.

The simplest way is to copy or rename your preferred WAV file to:

```text
%USERPROFILE%\.codex\hooks\codex_notify.wav
```

Then restart Codex / reload the VS Code Codex extension.

### Sound does not play

The worker tries your custom WAV file first, then several Windows notification WAV files, and finally falls back to `SystemSounds.Exclamation`. If your system sound scheme is muted, the popup may still appear without audible sound.
