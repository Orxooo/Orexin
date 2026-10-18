<p align="center">
  <a href="https://github.com/Orxooo/Orexin/releases/tag/v1.0.1"><img src="Assets/README/cover.svg" width="100%" alt="Orexin — Stay awake. Rest on time."></a>
</p>

<h1 align="center">Orexin</h1>
<p align="center"><strong>Keep your Mac awake while you work. Let it rest when the job is done.</strong></p>

<p align="center">
  <a href="https://github.com/Orxooo/Orexin/releases/tag/v1.0.1"><img src="https://img.shields.io/badge/Release-v1.0.1-56d7df?style=flat-square&amp;labelColor=14232e" alt="V1.0.1"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-8ba6b8?style=flat-square&amp;labelColor=14232e" alt="macOS 15 or later">
  <a href="https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml"><img src="https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main" alt="macOS compatibility CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6?style=flat-square&amp;labelColor=14232e" alt="GPL-3.0-only"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong><br><br>
  <a href="https://github.com/Orxooo/Orexin/releases/tag/v1.0.1"><strong>Download V1.0.1 ↗</strong></a> &nbsp; · &nbsp;
  <a href="#get-started">Installation</a> &nbsp; · &nbsp;
  <a href="https://github.com/Orxooo/Orexin/wiki">Handbook</a> &nbsp; · &nbsp;
  <a href="https://github.com/Orxooo/Orexin/discussions">Discussions</a>
</p>

---

Orexin is a native macOS menu-bar utility for builds, downloads, presentations, and focused work. Start a session, choose how the screen and lid should behave, and let the session end when your chosen condition is met.

**Stay awake → finish work → restore sleep.** The main window and menu-bar panel share the same state, with system readback after mode changes.

## A look inside

<a href="Assets/README/power-terminal.png"><img src="Assets/README/power-terminal.png" width="100%" alt="Orexin V0.1.0 Preview work modes screen in the Tron theme, showing normal sleep and the background and desktop presets"></a>

<p align="center"><sub>V0.1.0 Preview · Tron theme · Actual app screenshot, shown in Simplified Chinese</sub></p>

<table>
  <tr>
    <td width="50%"><a href="Assets/README/zima-blue.png"><img src="Assets/README/zima-blue.png" alt="Zima Blue theme with light panels and deep blue accents"></a></td>
    <td width="50%"><a href="Assets/README/blade-runner.png"><img src="Assets/README/blade-runner.png" alt="Blade Runner 2049 theme with dark panels and amber accents"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>Zima Blue</strong><br><sub>A calm, light workspace</sub></td>
    <td align="center"><strong>Blade Runner 2049</strong><br><sub>Amber light after dark</sub></td>
  </tr>
</table>

Three themes change both the interface palette and moon artwork. Available in 简体中文, 繁體中文, English, 日本語, Français, Deutsch, and Español, with optional short mechanical click sounds.

## Put a session in charge

| What you need | How Orexin helps |
| --- | --- |
| **Keep working with the lid closed** | The background preset keeps the system running after you approve the helper and authorize unlocked work for the session. |
| **Present or work at your desk** | The desktop preset prevents idle sleep while allowing normal sleep when you close the lid. |
| **Finish at the right moment** | End after a duration, at a time, when an app or process exits, or when a selected download finishes. |
| **Run a command and step away** | Run noninteractive foreground zsh commands concurrently, with separate wakefulness and logs; sleep is scheduled only after all overlapping requests succeed and other wakefulness sources have ended. |
| **Start from familiar conditions** | Combine power, display, device, app, network, or weekly schedule conditions. Manual actions take priority. |
| **Release wakefulness when needed** | Session completion, low-battery protection, and thermal protection share the cleanup path that restores sleep and password settings. |

Screen behavior is independent of the preset: choose **0% brightness, normal brightness, or system-timed display sleep**, or turn the display off once. Background and desktop presets each remember their screen choice.

[Full feature reference and limitations →](FEATURES.md)

## Get started

**Apple Silicon Mac · macOS 15 or later.** The current download is arm64.

1. Open the [V1.0.1 release](https://github.com/Orxooo/Orexin/releases/tag/v1.0.1) and download `Orexin-1.0.1-arm64.zip`.
2. Extract it, move `Orexin.app` to Applications, and open it. When upgrading, wait for commands and execution plans to finish and end wakefulness. If the old version has a background service, run the bundled CLI’s `service-stop`, then quit the interface and replace the app. Existing Orexin preferences and local data are retained.
3. Choose a preset and an end condition. For lid-closed work, approve the helper in Settings and personally authorize unlocked work in the native dialog.

> [!IMPORTANT]
> The download is Apple Development-signed and has not been Developer ID-notarized. macOS may block the first launch. Check the source and `SHA256SUMS.txt`, then follow the system's Privacy & Security prompt. You do not need to disable Gatekeeper or System Integrity Protection globally.

<details>
<summary><strong>Verify your download</strong></summary>

Download the ZIP and `SHA256SUMS.txt` into the same directory, then run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

`Orexin-1.0.1-arm64.zip: OK` confirms that the checksum matches.

</details>

<details>
<summary><strong>Authorization, displays, and sleep</strong></summary>

- **Enter your password only in the native authorization dialog.** Orexin does not store passwords or unlock a locked Mac. Only after you explicitly authorize unlocked work for that session does it temporarily disable the wake-password requirement; session cleanup, exit, or helper recovery restores immediate password protection.
- **Minimum brightness and display sleep behave differently.** Zero brightness keeps the display session available. Turning the display off may affect screenshots and UI automation that depend on it.
- **Normal sleep releases Orexin's own wakefulness controls.** Other apps and system settings can still affect when the Mac actually sleeps.
- **Unavailable observations stay unknown.** Wi-Fi names depend on location permission. Cisco VPN detection uses connection status exposed by macOS rather than guessing.

See the [security policy](SECURITY.md) and [feature reference](FEATURES.md).

</details>

## Task management and CLI

V1.0.0 is the first stable release, adding an independent background task service and execution plans alongside consistent controls, alignment, and spacing. Plans support dependencies, serial/parallel execution, concurrency limits, failure branches, and per-command logs. See the [execution-plan guide (Chinese)](docs/EXECUTION-PLANS.md).

Professional rules, power analysis, and reusable work profiles provide: nested conditions and read-only trials, observable assertion sources and a contextual timeline, and versioned JSON import/export with an exact preview. See the [configuration guide](docs/WORK-CONFIGURATION.md). Work profiles can include notifications and locally enabled outcome scripts, with a configuration snapshot captured when each task starts.

**Task Management** includes **Task list / Run command / Work profiles / Integrations**. Run commands concurrently, inspect each task's logs, actual exit code and wakefulness status, and release requests individually.

Finishing one task preserves the others. A cancellable 60-second sleep countdown starts only when all overlapping requests succeed and no manual work, session or rule still needs wakefulness. Releasing a request or stopping all wakefulness does not kill running commands.

After installing, use the bundled CLI without keeping the interface open:

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" help
"$orexin" run --title Build -- make
"$orexin" list --json
```

`run` wraps a foreground command and reports its actual result. External tools can also use `register`, `heartbeat`, `complete` and related lifecycle commands. The local interface is restricted to the current user and does not listen on a network port. Requests and plans run in the independent background service and survive closing or reopening the interface. Manual sessions, automatic rules, and interface-driven conveniences still depend on the interface process. Restarting the service marks unfinished work as lost without replaying commands or restoring old wakefulness requests.

See the [CLI and concurrent-request guide (Chinese)](docs/CLI.md) for options and integration examples. If the app is installed elsewhere, copy its actual path from Integrations.

## Build from source

Use **Xcode 26+ and Swift 6**. CI uses Xcode 26.3 to build, test, and package the app on macOS 15 and 26.

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

The app is written to `/tmp/orexin-dist/Orexin.app` with an ad hoc signature by default. Lid-closed operation requires the app and helper to be signed with the same Apple developer identity:

```sh
OREXIN_SIGN_IDENTITY='Certificate name or SHA-1' ./scripts/build-app.sh
```

`OREXIN_BUILD_DIR` and `OREXIN_OUTPUT_DIR` can move build products outside the repository. The build script does not register a system service or change system permissions.

<details>
<summary><strong>AppleScript and local data</strong></summary>

```applescript
tell application "Orexin"
    start session mode "desktop" for minutes 30
    session status
    -- end session
end tell
```

Scripts, shortcuts, and the interface share state verification. See the complete [Orexin.sdef dictionary](Resources/Orexin.sdef).

- Bundle ID: `com.orxooo.Orexin`
- Preference key prefix: `orexin.`
- Local history, command logs, and custom resources: `~/Library/Application Support/Orexin/`
- Legacy WakeMac data is neither migrated nor deleted automatically. Review logs for private information before sharing them.

</details>

## Make it better together

| Destination | Use it for |
| --- | --- |
| [Releases](https://github.com/Orxooo/Orexin/releases) | Downloads, release notes, and checksums |
| [Wiki](https://github.com/Orxooo/Orexin/wiki) | Installation and common questions |
| [Discussions](https://github.com/Orxooo/Orexin/discussions) | Questions, early ideas, and ways you use the app |
| [Issues](https://github.com/Orxooo/Orexin/issues/new/choose) | Reproducible bugs and concrete feature requests |
| [Private vulnerability reporting](https://github.com/Orxooo/Orexin/security/advisories/new) | Authentication, privilege, or privacy issues; keep exploit details private |

Documentation, translation, and focused code contributions are welcome. Read the [contribution guide](CONTRIBUTING.md) and [code of conduct](CODE_OF_CONDUCT.md) first.

## License

**GPL-3.0-only · © 2026 Orxooo.** Use, modification, and commercial use are permitted. Distributed derivatives must comply with the GPL's corresponding-source, license, and copyright-notice requirements. Third-party resources retain their own licenses; see [LICENSE](LICENSE) and [NOTICE](NOTICE).

<p align="center"><sub>Keep working. Rest when done.</sub></p>
