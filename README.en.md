<p align="center">
  <img src="Assets/README/cover.png" width="100%" alt="Orexin: a midnight-blue eclipse and amber orbital arcs. Stay awake. Rest on time.">
</p>

# Orexin

[简体中文](README.md) · **English**

[![Release](https://img.shields.io/github/v/release/Orxooo/Orexin?color=56d7df&label=release)](https://github.com/Orxooo/Orexin/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-8ba6b8)
[![CI](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)
[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6)](LICENSE)

Orexin is a macOS menu bar utility for controlling when your Mac stays awake and when it can sleep.

Use it for builds, downloads, presentations or long-running tasks, at your desk or with the lid closed. Timed sessions, automatic rules and command tasks let you choose when to stop keeping the Mac awake.

[Download latest](https://github.com/Orxooo/Orexin/releases/latest) · [Changelog](CHANGELOG.md) · [Handbook](https://github.com/Orxooo/Orexin/wiki)

![Orexin work modes in the Tron theme, shown in Simplified Chinese](Assets/README/orexin-1.0.3-modes.png)

## Features

- **Work modes:** Background Work prevents sleep with the lid closed. Desktop Work prevents idle sleep but allows sleep when the lid closes.
- **Screen controls:** Set brightness to 0%, keep normal brightness, follow the system display timer or turn the display off immediately. Each work mode remembers its setting.
- **Sessions:** End after a duration, at a set time, when an app or process exits, or when a download finishes.
- **Commands and plans:** Run commands concurrently with exit codes and logs. Define dependencies, concurrency limits and failure branches in JSON.
- **Rules and profiles:** Trigger work from power, display, device, app, network or time conditions. Supports nested conditions, trial runs and configuration import/export.
- **Protection and alerts:** Optional low-battery and thermal protection, service alerts, session-end warnings and update reminders, with system notifications and in-app popups. Updates are installed manually.

Includes Tron, Zima Blue and Blade Runner 2049 themes, with Simplified Chinese, Traditional Chinese, English, Japanese, French, German and Spanish. See the [feature reference](FEATURES.md) for details.

## Get started

Requires **Apple Silicon and macOS 15 or later**.

1. Download the Apple Silicon package (filename ending in `-arm64.zip`) from the [release page](https://github.com/Orxooo/Orexin/releases/latest), extract it and move `Orexin.app` to Applications.
2. Open the app and choose a work mode and end condition. Working with the lid closed requires helper approval in Settings.
3. To receive system notifications, allow them in **Messages & alerts** and send a test alert.

The package is **Apple Development-signed and has not been Developer ID-notarized**. If macOS blocks the first launch, check the download source and follow the Privacy & Security prompt. There is no need to disable SIP or Gatekeeper globally.

To verify the download, place the ZIP and the release's `SHA256SUMS.txt` in the same directory:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

### Upgrading

Wait for commands and plans to finish, end all keep-awake requests, then stop the background task service:

```sh
/Applications/Orexin.app/Contents/Helpers/orexin service-stop
```

Quit Orexin, replace the app and reopen it. Skip this step if your old version has no `service-stop` command. Preferences, history and logs are retained; old tasks are not replayed.

### Before use

- “Keep unlocked while working” is optional and requires separate authorization. It disables the wake-password requirement for the session and restores immediate password protection when work ends. Orexin does not store passwords or unlock a locked Mac.
- Zero brightness differs from display sleep. Turning the display off may affect screenshots or UI automation that depend on it.
- Returning to Normal Sleep releases Orexin's requests. Other apps may still prevent sleep.
- Thermal protection uses macOS thermal-pressure levels, not Celsius readings. Cooling does not restart stopped work.

## Task management and CLI

Background commands and plans continue after you quit the interface. Manual sessions and automatic rules require the interface process. Restarting the service marks unfinished tasks as lost without rerunning them.

The CLI is bundled with the app:

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" run --title Build -- make
"$orexin" list --json
```

By default, finishing a command releases that task's keep-awake request. Add `--after sleep` to start a 60-second sleep countdown after success. All overlapping requests must succeed, and no other session or rule may still require wakefulness. Releasing a request does not terminate its command.

If “Keep unlocked while working” is enabled, authorize it in the interface first; the CLI does not show password dialogs. See the [CLI guide](docs/CLI.md) and [execution-plan guide](docs/EXECUTION-PLANS.md) for options, external integrations and plan formats.

## Build from source

Requires **Xcode 26+ and Swift 6**.

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

The output is `/tmp/orexin-dist/Orexin.app`, signed ad hoc by default. Lid-closed operation requires the app and helper to use the same Apple developer certificate:

```sh
OREXIN_SIGN_IDENTITY='Certificate name or SHA-1' ./scripts/build-app.sh
```

Use `OREXIN_BUILD_DIR` and `OREXIN_OUTPUT_DIR` to set build and output directories. CI is configured for Xcode 26.3 on macOS 15 / 26; see [Actions](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml) for results.

## Documentation and feedback

- [Work profiles](docs/WORK-CONFIGURATION.md) · [AppleScript dictionary](Resources/Orexin.sdef) · [Security](SECURITY.md)
- [Report a bug](https://github.com/Orxooo/Orexin/issues/new/choose) · [Discussions](https://github.com/Orxooo/Orexin/discussions) · [Private vulnerability reports](https://github.com/Orxooo/Orexin/security/advisories/new)
- [Contributing](CONTRIBUTING.md) · [Code of conduct](CODE_OF_CONDUCT.md)

Local history and logs are stored in `~/Library/Application Support/Orexin/`. Legacy WakeMac data is not migrated or deleted automatically. Check logs for private information before sharing them.

## License

[GPL-3.0-only](LICENSE) · © 2026 Orxooo. Third-party licenses are listed in [NOTICE](NOTICE).
