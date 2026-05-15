# Codex 任务提醒器

这是一个面向 Windows 的 Codex PowerShell hooks 工具。它可以在以下场景弹出桌面提醒并播放提示音：

- Codex 一轮任务完成时：`Stop` hook；
- Codex 需要人工授权时：`PermissionRequest` hook。

英文文档：[README.md](README.md)

## 仓库内容

```text
hooks/
  codex_done.ps1                 # Stop hook 入口：任务完成提醒
  codex_permission_notify.ps1    # PermissionRequest hook 入口：授权提醒
  codex_notify_worker.ps1        # 公共弹窗 + 声音提醒 worker
scripts/
  test-notification.ps1          # 本地快速测试脚本
examples/
  hooks.json                     # 手动配置 hooks.json 示例
  config.toml.snippet            # config.toml 最小配置片段
install.ps1                      # 安装脚本，安装到 ~/.codex
```

## 环境要求

- Windows 桌面环境；
- PowerShell 5.1 或更高版本；
- 支持 hooks 的 Codex CLI / VS Code Codex；
- Codex hooks 功能已启用：

```toml
[features]
hooks = true
```

不要再使用已废弃的旧配置：

```toml
[features]
codex_hooks = true
```

## 快速安装

克隆仓库：

```powershell
git clone https://github.com/My-sec/codex-task-notifier.git
cd codex-task-notifier
```

安装到默认 Codex 目录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

默认安装目录是：

```text
%USERPROFILE%\.codex
```

如果你的 Codex home 是自定义路径：

```powershell
$env:CODEX_HOME = "<your-codex-home>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -CodexHome $env:CODEX_HOME
```

生成的 hook 命令不会写入你的 Windows 用户名。它会在运行时优先从 `CODEX_HOME` 解析 Codex home；如果没有设置 `CODEX_HOME`，则使用 `%USERPROFILE%\.codex`。

安装脚本写入的 hook 命令使用 `powershell.exe -EncodedCommand`。这样可以避免 Windows 上外层 PowerShell 提前展开 `$env:CODEX_HOME` 或 `$codexHome`，从而导致 hook 以 `exit code 1` 失败。

安装脚本会完成以下操作：

1. 将三个 hook 脚本复制到 `<CodexHome>\hooks`；
2. 创建或合并 `<CodexHome>\hooks.json`；
3. 确保 `<CodexHome>\config.toml` 中包含 `[features].hooks = true`；
4. 修改前自动备份已有的 `hooks.json` 和 `config.toml`。

如果 `hooks.json` 已经存在，安装脚本会保留已有 hook 事件和命令。它只会移除旧的 `codex_done.ps1` / `codex_permission_notify.ps1` 项，然后添加当前版本的提醒 hook。

## 必须进行的 Codex 审核步骤

安装后，请重启 Codex 或重新加载 VS Code Codex 扩展。

Codex 可能会提示：

```text
1 hook needs review before it can run. Open /hooks to review it.
```

此时需要在 Codex 对话中输入：

```text
/hooks
```

然后审核并允许这两个本地 PowerShell hook 命令。

这是 Codex 的 hook 安全机制，不能只靠文件配置绕过。

## 手动安装

1. 将以下三个脚本：

```text
hooks\codex_done.ps1
hooks\codex_permission_notify.ps1
hooks\codex_notify_worker.ps1
```

复制到：

```text
%USERPROFILE%\.codex\hooks
```

2. 创建或更新：

```text
%USERPROFILE%\.codex\hooks.json
```

可以参考 [examples/hooks.json](examples/hooks.json)。示例会在运行时通过 `CODEX_HOME` 或 `%USERPROFILE%` 解析 hook 目录，不需要硬编码包含用户名的绝对路径。

3. 确保：

```text
%USERPROFILE%\.codex\config.toml
```

包含：

```toml
[features]
hooks = true
```

4. 重启 Codex，并通过 `/hooks` 审核允许 hook。

## 本地快速测试

安装后，在仓库目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-notification.ps1 -Kind both
```

正常情况下你会看到：

- “任务已完成”弹窗；
- “需要授权确认”弹窗；
- 一次简短提示音。

运行日志会写入已安装脚本旁边：

```text
%USERPROFILE%\.codex\hooks\codex_done.log
```

## 关于授权提醒的注意事项

`PermissionRequest` 弹窗只有在 Codex 真正需要人工授权时才会触发。

如果你的 Codex 配置是：

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

那么普通任务通常不会出现授权请求。此时“任务完成提醒”仍然可以使用，但“需要授权提醒”可能很少触发，甚至不会触发。

如果你想测试授权提醒，可以使用会请求授权的配置，例如：

```toml
approval_policy = "on-request"
```

## 安全说明

- 在 `/hooks` 中批准之前，请先自行检查这些 PowerShell 脚本；
- 脚本只使用本地 Windows API 显示弹窗和播放声音；
- 脚本不会发起网络请求；
- 安装脚本在修改 Codex 配置前会自动备份原文件。

## 常见问题

### 没有弹窗

请检查：

1. `hooks.json` 是否位于 Codex home 目录下；
2. `config.toml` 中是否存在 `[features].hooks = true`；
3. 安装后是否重启了 Codex；
4. 是否已经通过 `/hooks` 审核允许 hook；
5. 是否可以手动运行本地快速测试脚本。

### 任务完成提醒有效，但授权提醒无效

这通常是正常现象。原因是 Codex 当前配置可能不会请求人工授权。请参考“关于授权提醒的注意事项”。

### 有弹窗但没有声音

worker 会尝试播放多个 Windows 系统通知音，并在失败时回退到 `SystemSounds.Exclamation`。如果你的系统提示音被静音，可能只有弹窗没有声音。
