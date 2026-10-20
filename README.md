# Codex Usage Widget

A Windows widget for **OpenAI Codex**, ported from [Clawd Usage WinWidget](https://github.com/Enhed/clawd-usage-winwidget), the original widget for **Claude Code**. It keeps Clawd, the animated scenes, skins and settings style, and connects them to Codex usage and activity.

[Русская документация](README.ru.md) · [Download ZIP](https://github.com/Enhed/codex-usage-widget/archive/refs/heads/main.zip) · [Original Claude widget](https://github.com/Enhed/clawd-usage-winwidget)

![Widget preview — sample data](docs/preview-classic.png)

## Features

- Codex quota windows, used percentages, local reset times and a tray icon.
- Clawd runs while Codex is working, dozes after **10 minutes** without chat updates and sleeps after **20 minutes**.
- Ten theme choices, including animated Space, Ocean, Halloween and Cyberpunk scenes; pixel skins with hover previews.
- Settings tabs with immediate saving, scale and opacity controls, always-on-top and persistent position.
- Weather and day/night sky, OpenAI service status, account details and optional token activity.
- Seven days of recorded quota history and projects grouped by recent chats.
- Russian and English UI. Windows PowerShell 5.1 and built-in Windows libraries; no third-party runtime packages.

The assistant chat, recurring tasks, command execution, reminders, lists and computer advisor from the Claude widget are omitted. This port has its own Codex data integration and does not use the original app's updater.

## Start

1. Install Codex CLI on PATH and sign in using `codex login` with your ChatGPT account.
2. Download the ZIP above and extract the **whole folder**.
3. Double-click `start-widget.vbs`.

Requires Windows 10/11 and Windows PowerShell 5.1. Administrator access is not required. The widget uses your existing Codex login and `CODEX_HOME`; it does not change Codex settings.

Drag the title to move. The gear opens settings, the triangle expands details, the minus hides to the tray, and the cross exits. Right-click Clawd for animation and weather previews. Use the tray menu or the details link to refresh quotas manually.

## Themes and settings

| Space | Ocean |
| --- | --- |
| ![Space](docs/preview-space.png) | ![Ocean](docs/preview-ocean.png) |

![Settings](docs/settings-look.png)

## How data is read

The large number is the **used** percentage of the first available main Codex quota window. All other windows returned by Codex appear below it. Quotas refresh every minute by default. A failed refresh keeps the previous sample and marks it stale; missing windows are not treated as zero.

Quotas, account details and recent threads come from the [Codex App Server protocol](https://learn.chatgpt.com/docs/app-server). No model turns are started. API-key-only accounts may not expose ChatGPT subscription quotas; token activity appears only when the service supports it.

Activity is checked separately every five seconds. On supported Codex installations, the widget uses Windows SQLite to read only IDs, timestamps and execution states from `state_5.sqlite` and `thread_history_1.sqlite`. It does not read message bodies. These internal schemas may change in future Codex versions; App Server supplies fallback metadata when the databases are absent. The recent-chat line includes up to 100 threads and is not an active-agent counter.

Weather uses ipwho.is, Open-Meteo and met.no. Turn off sky/weather in settings to disable these requests, or set `weatherLat` and `weatherLon` in the configuration. Service status is the overall OpenAI status.

## Files

```text
src/           application, Codex client and UI/animation modules
ui/            XAML layouts
assets/skins/  pixel skins
data/         local configuration, history and error log (ignored by Git)
tools/         checks and diagnostics
docs/          previews generated with sample data
```

Settings live in `data/config.json` and reload while running. History begins with the widget's first run. Personal data, logs and local backups are excluded from this repository. Updates are manual: close the widget and replace the application files, keeping `data/`.

## Checks

```powershell
# Read real quotas without opening a window
powershell.exe -NoProfile -ExecutionPolicy Bypass -File widget.ps1 -Check
# Run syntax, quota, settings, animation and persistence checks
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/smoke.ps1
# Inspect activity timestamps and states without displaying chat contents
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/check-activity.ps1
```

Preview checks close automatically and use isolated data. PowerShell sources use 5.1 syntax, UTF-8 BOM and CRLF. Errors are written to `data/widget-error.log`.

## Credits and license

Based on **[Clawd Usage WinWidget](https://github.com/Enhed/clawd-usage-winwidget)** by **Venger Sergey**. The mascot, skins, themes and substantial visual code are adapted from that project. This is a Codex port of the Claude Code widget, not an official OpenAI product.

MIT licensed; the original copyright notice and license are retained in [LICENSE](LICENSE).
