# Kitbag

A native macOS menu bar app (SwiftUI + AppKit, macOS 14+) with small tools you can switch on or off. The popup holds the tools; the Kitbag window (menu ▸ Settings) has a page per tool, Appearance settings and a terminal (⌘J).

- 🗂️ **File Shelf** – drop files, text, links or images, then drag them anywhere
  - 🔄 Convert PNG / JPG / HEIC / TIFF / PDF
  - 🗜️ Compress images (PNG palette reduction)
  - 🧹 Remove hidden metadata
- 📋 **Clipboard** – remembers what you copy
  - ⌨️ ⌥⌘V opens the history at the pointer: arrows to pick, Enter to paste
  - 🔎 Type to search, 📌 pin, pause or clear from the menu
- 🔐 **Authenticator** – two-factor codes (TOTP and Steam Guard) in the menu bar
  - 📷 Scan a QR code from your screen, an image or the clipboard; or enter it by hand
  - 🔎 Search, pin, click a code to copy it (hidden from clipboard history, cleared after 30 s)
  - 💾 JSON backup and restore from the settings page; accounts live in the Keychain
- 🎙️ **Dictation** – speak anywhere, get cleaned-up text pasted
  - ⌨️ Global shortcut or Globe key
  - 🧠 Apple or local Whisper speech to text
  - ✨ Clean-up with Claude or local Gemma
  - 📊 Usage dashboard
- 📈 **System Monitor** – CPU, memory, storage, network and battery
- ⚡ **Speed Test** – download, upload and latency
- 🔊 **Audio** – pick output and input devices
- 🛠️ **Dev Tools**
  - 🎨 Color picker and 📏 screen ruler
  - 🐳 Docker, 🍃 MongoDB, 🐘 PostgreSQL switches
  - 🟢 Node.js (nvm) and 🐍 Python (pyenv) versions
- 🚀 **Apps** – start or quit Google Drive, Proton Drive, Wispr Flow and FineTune
- 📡 **Blip** – send shelf files with one click
- 🔄 **Updates** – Kitbag checks GitHub for a newer release about once a day and can install it for you
  - ✅ Every download is checked (SHA-256, and the signature must match the app you are running) and the old app is restored if the new one doesn't start
  - 🚀 Publish a release with `scripts/release.sh patch|minor|major` (see the header of that script)
- 📶 **Wi-Fi and Bluetooth buttons** – status and quick dropdowns
