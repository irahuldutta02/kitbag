# Kitbag

A native macOS menu bar app (SwiftUI + AppKit, macOS 14+) hosting small tools you can switch on or off in Settings.

- **File Shelf** – drop files/folders onto a stack, then drag the whole stack into any folder or app. A Copy | Move switch decides what the drop does; a setting clears the shelf after drops. Stores only security-scoped bookmarks.
- **System Monitor** – CPU, memory and storage rings, network, disk, battery (with health). Click CPU or Memory for the top apps (grouped by source) with a Quit button. Polls only while its tab is visible.
- **Speed Test** – on-demand download/upload/latency test against Cloudflare's public speed test servers.
- **Blip** (integration, listed in Settings only when Blip is installed) – adds "Send with Blip" to the File Shelf (click it, or drop files on it); Blip then shows its own people and devices to send to. Settings can start Blip.
- **Audio** – choose the default output (one or several at once, through a Multi-Output device) and input device.
- **Wi-Fi and Bluetooth buttons** (top corner of the menu) – show whether Wi-Fi is on/connected and whether a Bluetooth device is connected, and open the real macOS Wi-Fi/Bluetooth dropdown (or Control Center's) on click. Needs the Accessibility permission, which Kitbag asks for with a walkthrough on first click.
- **Dev Tools** – two launchers: an on-screen color picker and a drag-to-measure ruler. Results (HEX/RGB/HSL, points/pixels) appear in a popup next to the cursor and the main value is copied.

Note: listing and quitting other processes needs the `process-info*`/`signal` sandbox exceptions in `App/Resources/Kitbag.entitlements`. That is fine for Developer ID/notarized distribution but not for the Mac App Store.

## Layout

```
Core/            KitbagTool protocol, ToolManager (registry), shared UI
Tools/<Tool>/    Sources + Tests per tool; tools import only KitbagCore, never each other
App/             Menu bar app, Settings, Start at login; App/Sources/AllTools.swift is the one registration point
scripts/         build.sh, measure-memory.sh
```

Add a tool: create `Tools/<Name>` (a target in `Package.swift`), expose a `ToolDescriptor`, add it to `AllTools.swift`.

## Building

Prerequisites: macOS 14+, Swift toolchain (Xcode or Command Line Tools). Optional: `create-dmg` (falls back to `hdiutil`).

```bash
./scripts/build.sh
```

Output: `release/Kitbag-<version>.dmg` (version is read from `App/Resources/Info.plist`).