import AppKit
import KitbagCore
import SwiftUI

/// The Authenticator page in the Kitbag window: options, backup and restore, permissions.
struct AuthenticatorSettingsView: View {
  @ObservedObject var model: AuthenticatorModel

  var body: some View {
    Section {
      ShortcutRecorderRow(
        "Open Authenticator", current: model.shortcut,
        defaultShortcut: AuthenticatorModel.defaultShortcut,
        onPause: { model.pauseHotKey($0) }, onSet: { model.setShortcut($0) })
    } header: {
      Text("Shortcut")
    } footer: {
      Text("Press it anywhere to open Authenticator with the search field ready. Return copies the first match.")
    }

    Section("Accounts") {
      HStack {
        Text(model.entries.count == 1 ? "1 account" : "\(model.entries.count) accounts")
        Spacer()
        Button("Add…") { model.addManually() }.controlSize(.small)
        Button("Scan Screen") { model.scanScreen() }.controlSize(.small)
        Button("Use Camera") { model.scanCamera() }.controlSize(.small)
      }
      Toggle("Clear a copied code from the clipboard after 30 seconds", isOn: $model.clearAfterCopy)
      if let e = model.storageError { Text(e).font(.caption).foregroundStyle(.red) }
    }

    Section {
      ForEach(ImportSource.allCases) { source in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Label(source.name, systemImage: source.symbol)
            Spacer()
            if source == .google {
              Menu("Import…") {
                Button("Scan QR Code on Screen") { model.scanScreen(forImport: true) }
                Button("Scan QR Code with Camera") { model.scanCamera(forImport: true) }
                Button("Scan QR Code from Image…") { model.scanImageFile(forImport: true) }
                Button("Paste Link or QR from Clipboard") { model.pasteFromClipboard(forImport: true) }
              }
              .menuStyle(.button).controlSize(.small).fixedSize()
            } else {
              Button("Choose File…") { model.importFrom(source) }.controlSize(.small)
            }
          }
          Text(source.howTo).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
      }
    } header: {
      Text("Import")
    } footer: {
      Text("Proton Authenticator and 2FAS exports can be plain or password-protected; you are asked for the password when needed. Google Authenticator can only export QR codes, so scan each one it shows. Imported accounts are added next to yours and never replace an existing account.")
    }

    Section {
      LabeledContent("Last backup") {
        if let d = model.lastBackup {
          Text(d, format: .dateTime.day().month().year().hour().minute())
        } else {
          Text("Never").foregroundStyle(.orange)
        }
      }
      if model.needsBackup && model.lastBackup != nil {
        Label("Accounts changed since your last backup.", systemImage: "exclamationmark.circle")
          .font(.callout).foregroundStyle(.orange)
      }
      HStack {
        Button { model.backUp() } label: { Label("Back Up…", systemImage: "square.and.arrow.up") }
          .disabled(model.entries.isEmpty)
        Button { model.restoreBackup() } label: { Label("Restore…", systemImage: "square.and.arrow.down") }
      }
    } header: {
      Text("Backup")
    } footer: {
      Text("A backup is a JSON file with all your accounts, including their secrets, so anyone who has it can create your codes. Keep it somewhere private. Restoring adds the accounts you don't have yet and never overwrites existing ones.")
    }

    Section {
      LabeledContent("Screen recording") {
        if CGPreflightScreenCaptureAccess() {
          Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
          Button("Open Settings") { Dialogs.openScreenRecordingSettings() }.controlSize(.small)
        }
      }
      LabeledContent("Camera") {
        if CameraScanner.cameraAllowed {
          Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if CameraScanner.cameraDenied {
          Button("Open Settings") { CameraScanner.openCameraSettings() }.controlSize(.small)
        } else {
          Text("Asked when you first use it").foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("Permissions")
    } footer: {
      Text("Screen recording is only needed to scan a QR code on your screen, and the camera only to scan one held up to it. Screenshots and camera pictures are read on this Mac and never saved. Accounts are stored in your Keychain and never leave this Mac.")
    }

    Section {
      Button("Remove All Accounts…", role: .destructive) { model.confirmRemoveAll() }
        .disabled(model.entries.isEmpty)
    }
  }
}
