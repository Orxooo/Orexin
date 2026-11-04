# Changelog

[简体中文](CHANGELOG.md) · [繁體中文](CHANGELOG.zh-Hant.md) · **English** · [日本語](CHANGELOG.ja.md) · [Français](CHANGELOG.fr.md) · [Deutsch](CHANGELOG.de.md) · [Español](CHANGELOG.es.md)

[Back to README](README.md)

See [Releases](https://github.com/Orxooo/Orexin/releases) for downloads and upgrade instructions.

## V1.1.0 — 2026-11-04

### Added

- Choose between cockpit and horizontal menu bar panels in Appearance. Use the arrows to browse shortcuts in the horizontal panel.
- Tron, Zima Blue and Blade Runner 2049 have new artwork that rotates randomly, with different animations for each scene.

### Improved

- Work modes are now Awake and Normal. Configure the screen, lid, screen saver and unlocked-work options as needed. Work Sessions is now Wake Configuration.
- Reorganized the work mode, wake configuration, automatic trigger, automatic teardown and preferences pages, with consistent buttons, switches and status displays.

### Fixed

- Starting a new awake session restores normal brightness after a previous minimum-brightness session.
- Restoring the screen from minimum brightness updates the current work request, so the old setting does not dim it again.
- Fixed Wi-Fi and Bluetooth permission controls when access has already been granted or denied.

## V1.0.5 HotFix 4 — 2026-11-02

### Fixed

- Fixed brightness recovery with Esc or the brightness keys on some unlocked Macs.
- Fixed Input Monitoring permission checks and messages. Restoring the screen keeps the work session running.

## V1.0.5 HotFix 3 — 2026-10-31

### Added

- Add the default-on “Restore with Esc / brightness keys” option. During desktop work at minimum brightness, Esc or either display brightness key restores the previous brightness without ending work. Select minimum brightness again to reapply dimming.

### Improved

- Synchronize recovery state and Input Monitoring permission hints between the background service and interface, preserving existing wake recovery.

## V1.0.5 HotFix 2 — 2026-10-28

### Improved

- Keeping the Mac or display awake and preventing the screen saver do not require a password. Unlocked work reuses valid authorization and checks it again after the process changes.
- Authorization and session-start errors follow the selected language. Older English authorization notices can also be translated without changing their stored history.

### Fixed

- When the background service disconnects briefly, Orexin reconnects and restores active work using its existing approval. Stopped work stays stopped, and commands and plans are not run again.
- Closed-lid work resumes after a brief service interruption. Policy rejections and expired authorization still require attention, and a fresh start restores password protection.

## V1.0.5 HotFix 1 — 2026-10-28

### Improved

- Clarified desktop mode and authorization messages. Update checks now recognize stable hotfixes.

### Fixed

- Fixed an error that reported an approved helper as unauthorized. Failed connections can be retried.
- Idle display locking pauses while display sleep prevention is active. Saved idle rules remain unchanged.

## V1.0.5 — 2026-10-27

### Improved

- Closing the lid again or selecting minimum brightness reapplies dimming. Saved screen settings are kept.

### Fixed

- Fixed the screen becoming dark again after opening the lid, waking the display or unlocking during background work. The previous brightness returns while tasks continue.

## V1.0.4 — 2026-10-26

### Improved

- Accessibility authorization now reports its state and opens System Settings. Pointer movement explains why it is waiting or paused.
- Reorganized the trigger rule editor with labeled fields, collapsible advanced options, fixed Save and Cancel actions, and fewer nested borders and scroll areas.

### Fixed

- Fixed session effect switches being overridden by display policy. Screen saver prevention can be turned off independently; enabling it selects a compatible display policy.

## V1.0.3 — 2026-10-25

### Added

- Added Messages & alerts to retain update notices, service errors, expired requests, session-end warnings and thermal-protection messages.
- Added popups for important events and macOS notifications, avoiding duplicate reminders or delayed alerts for conditions that have already recovered.

### Improved

- Check for updates after launch and every 6 hours. Each version triggers only one reminder; downloading and installing updates remains manual.
- Updated the Chinese and English user documentation and screenshots.

## V1.0.2 — 2026-10-22

### Fixed

- Fixed the main window and quick panel failing to close, including the Close menu item and `⌘W`. The menu bar and background tasks continue running after a window closes.

## V1.0.1 — 2026-10-18

### Fixed

- Fixed the menu panel flickering every second, text ghosting and layout jitter while work is running.

## V1.0.0 — 2026-10-18

First stable release.

### Added

- Added a separate background task service so commands and execution plans continue after the interface quits.
- Added JSON execution plans with dependencies, sequential and parallel execution, concurrency limits, failure branches and per-task logs.
- Added cancellation of commands in a plan that have not yet started. Running commands continue; restarting the service does not replay tasks.

### Improved

- Standardized buttons, selectors and switches; fixed card, filter and log layouts; improved narrow-window layouts and keyboard operation.

### Fixed

- Fixed the bundled CLI failing to start the background service.

## V0.3.0 Preview.1 — 2026-10-18

The release page is named V0.3.1 Preview; the original tag is `v0.3.0-preview.1`, and the app version is `0.3.0`.

### Added

- Added advanced rules with nested conditions, priorities, sustained matching, cooldowns and trial runs.
- Added power analysis to view system power assertions, identifiable source processes and an event timeline.
- Added work profiles and JSON import/export, with difference previews, merging and replacement. Imported rules and scripts must be enabled locally.
- Added CLI support for work profiles, rule trial runs, power queries and configuration import/export.

### Improved

- Corrected task-management alignment and narrow-window layouts, and fixed Xcode 26.3 compilation errors.

## V0.2.0 Preview — 2026-10-14

### Added

- Added concurrent task management with separate exit codes, logs and keep-awake status for each task.
- Added the bundled `orexin` CLI for running commands, registering external tasks, sending heartbeats and querying status.
- Finishing one task does not affect others. A 60-second sleep countdown can begin when all overlapping requests succeed and no other source still requires wakefulness.
- Added individual request release and a stop-all keep-awake action, without terminating running commands.

### Improved

- Adjusted the task-page layout and completed its text in all seven languages.

## V0.1.0 Preview — 2026-10-12

First public preview.

### Added

- Added background and desktop work modes, timed and conditional sessions, screen brightness controls and display sleep.
- Added automatic triggers, command tasks, thermal and low-battery protection, and local history.
- Added a menu-bar panel, three themes, seven languages and optional click sounds.
- Added update checks for preview releases.
- Released under GPL-3.0-only.

### Fixed

- Fixed repeated sleep requests after timed sessions ended and horizontal shifts when switching certain pages.
