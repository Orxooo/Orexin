# Changelog

[简体中文](CHANGELOG.md) · [繁體中文](CHANGELOG.zh-Hant.md) · **English** · [日本語](CHANGELOG.ja.md) · [Français](CHANGELOG.fr.md) · [Deutsch](CHANGELOG.de.md) · [Español](CHANGELOG.es.md)

[Back to README](README.md)

See [Releases](https://github.com/Orxooo/Orexin/releases) for downloads and upgrade instructions.

## V1.0.5 — 2026-10-27

- Fixed the screen returning to zero brightness after opening the lid, waking the display, or unlocking during background work. Original brightness is restored and dimming pauses while tasks continue.
- Closing the lid again or explicitly selecting minimum brightness reapplies dimming. Saved screen presets are preserved, including when the independent background service owns the work.

## V1.0.4 — 2026-10-26

- Fixed session effect switches being overridden by display policy. Screen saver prevention can be turned off independently; enabling it selects a compatible display policy.
- Accessibility authorization now reports its state and opens System Settings. Pointer movement explains why it is waiting or paused.
- Reorganized the trigger rule editor with labeled fields, collapsible advanced options, fixed Save and Cancel actions, and fewer nested borders and scroll areas.

## V1.0.3 — 2026-10-25

- Added Messages & alerts to retain update notices, service errors, expired requests, session-end warnings and thermal-protection messages.
- Added popups for important events and macOS notifications, avoiding duplicate reminders or delayed alerts for conditions that have already recovered.
- Check for updates after launch and every 6 hours. Each version triggers only one reminder; downloading and installing updates remains manual.
- Updated the Chinese and English user documentation and screenshots.

## V1.0.2 — 2026-10-22

- Fixed the main window and quick panel failing to close, including the Close menu item and `⌘W`. The menu bar and background tasks continue running after a window closes.

## V1.0.1 — 2026-10-18

- Fixed the menu panel flickering every second, text ghosting and layout jitter while work is running.

## V1.0.0 — 2026-10-18

First stable release.

- Added a separate background task service so commands and execution plans continue after the interface quits.
- Added JSON execution plans with dependencies, sequential and parallel execution, concurrency limits, failure branches and per-task logs.
- Added cancellation of commands in a plan that have not yet started. Running commands continue; restarting the service does not replay tasks.
- Standardized buttons, selectors and switches; fixed card, filter and log layouts; improved narrow-window layouts and keyboard operation.
- Fixed the bundled CLI failing to start the background service.

## V0.3.0 Preview.1 — 2026-10-18

The release page is named V0.3.1 Preview; the original tag is `v0.3.0-preview.1`, and the app version is `0.3.0`.

- Added advanced rules with nested conditions, priorities, sustained matching, cooldowns and trial runs.
- Added power analysis to view system power assertions, identifiable source processes and an event timeline.
- Added work profiles and JSON import/export, with difference previews, merging and replacement. Imported rules and scripts must be enabled locally.
- Added CLI support for work profiles, rule trial runs, power queries and configuration import/export.
- Corrected task-management alignment and narrow-window layouts, and fixed Xcode 26.3 compilation errors.

## V0.2.0 Preview — 2026-10-14

- Added concurrent task management with separate exit codes, logs and keep-awake status for each task.
- Added the bundled `orexin` CLI for running commands, registering external tasks, sending heartbeats and querying status.
- Finishing one task does not affect others. A 60-second sleep countdown can begin when all overlapping requests succeed and no other source still requires wakefulness.
- Added individual request release and a stop-all keep-awake action, without terminating running commands.
- Adjusted the task-page layout and completed its text in all seven languages.

## V0.1.0 Preview — 2026-10-12

First public preview.

- Added background and desktop work modes, timed and conditional sessions, screen brightness controls and display sleep.
- Added automatic triggers, command tasks, thermal and low-battery protection, and local history.
- Added a menu-bar panel, three themes, seven languages and optional click sounds.
- Added update checks for preview releases.
- Fixed repeated sleep requests after timed sessions ended and horizontal shifts when switching certain pages.
- Released under GPL-3.0-only.
