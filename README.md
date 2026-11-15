# Kitbag

A native macOS menu bar app (SwiftUI + AppKit, macOS 14+) with small tools you can switch on or off. The popup holds the tools; the Kitbag window (menu ▸ Settings) has a page per tool, Appearance settings and a terminal (⌘J).

- **File Shelf** – drop files onto a stack, then drag it into any folder or app (Copy or Move).
- **System Monitor** – CPU, memory, storage, network and battery; click CPU or Memory for the top apps.
- **Speed Test** – download, upload and latency against Cloudflare.
- **Audio** – pick the output (one or several) and input device.
- **Dev Tools** – color picker, screen ruler, and on/off switches for Docker, MongoDB and PostgreSQL, shown with their real logos. Each can be installed and uninstalled from the window.
- **Apps** – quick on/off switches to start or quit Google Drive, Proton Drive, Wispr Flow and FineTune without opening them (they start in the background).
- **Blip** – adds a Blip row to the File Shelf with an on/off switch and a **Send** button (it appears once Blip is on and the shelf has files; you can also drop files straight onto the row). Blip is only ever started and stopped by hand. Installed and removed from the File Shelf page.
- **Wi-Fi and Bluetooth buttons** – show status and open the macOS dropdowns (needs Accessibility permission).