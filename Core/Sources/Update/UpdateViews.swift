import SwiftUI

/// Explicit colors: the system ones lose their color on glass surfaces.
private enum UpdateColors {
  static let bad = Color(red: 0.95, green: 0.27, blue: 0.23)
  static let good = Color(red: 0.18, green: 0.70, blue: 0.36)
}

/// The Updates section of the Settings page.
public struct UpdatesSection: View {
  @ObservedObject var updater: Updater
  @MainActor public init(updater: Updater? = nil) { self.updater = updater ?? Updater.shared }

  public var body: some View {
    Section {
      LabeledContent("Version") { Text(updater.currentVersion.description).monospacedDigit() }
      status
      HStack {
        Button("Check for Updates") { updater.checkNow() }.disabled(updater.isBusy || updater.pendingRelease != nil)
        Spacer()
        if let d = updater.lastChecked {
          Text("Last checked \(d, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
        }
      }
      Toggle("Check for updates automatically", isOn: $updater.automatic)
    } header: {
      Text("Updates")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text("Kitbag asks GitHub for the newest release about once a day. Nothing is installed until you say so, and every download is checked before it replaces the app.")
        if !updater.hasStableSignature {
          Text("This copy of Kitbag isn't signed with a stable certificate, so macOS may ask you to allow Accessibility, Screen Recording and Keychain access again after an update. Run scripts/setup-signing.sh once to avoid that.")
        }
      }
    }
  }

  @ViewBuilder private var status: some View {
    switch updater.state {
    case .idle:
      EmptyView()
    case .checking:
      HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…") }
    case .upToDate:
      Label("Kitbag is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(UpdateColors.good)
    case .available(let r):
      VStack(alignment: .leading, spacing: 8) {
        Label("Kitbag \(r.versionText) is available", systemImage: "arrow.down.circle.fill")
          .font(.callout.weight(.semibold))
        if let d = r.published { Text("Released \(d, format: .dateTime.day().month().year())").font(.caption).foregroundStyle(.secondary) }
        notes(r)
        HStack {
          if updater.installBlocker == nil {
            Button("Update") { updater.update() }.buttonStyle(.borderedProminent)
          } else {
            Button("Download…") { updater.openReleasePage() }.buttonStyle(.borderedProminent)
          }
          Button("Skip This Version") { updater.skip() }
          Button("View on GitHub") { updater.openReleasePage() }
        }
        if let b = updater.installBlocker { Text(b).font(.caption).foregroundStyle(.secondary) }
      }
    case .downloading(let p):
      VStack(alignment: .leading, spacing: 6) {
        Text("Downloading… \(Int(p * 100))%")
        ProgressView(value: p)
      }
    case .preparing(let r):
      HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking Kitbag \(r.versionText)…") }
    case .ready(let r):
      VStack(alignment: .leading, spacing: 8) {
        Label("Kitbag \(r.versionText) is ready to install", systemImage: "checkmark.seal.fill").foregroundStyle(UpdateColors.good)
        Text("Kitbag will quit and open again in a few seconds.").font(.caption).foregroundStyle(.secondary)
        Button("Restart Now") { updater.restart() }.buttonStyle(.borderedProminent)
      }
    case .installing:
      HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Restarting…") }
    case .failed(let message):
      VStack(alignment: .leading, spacing: 6) {
        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(UpdateColors.bad).font(.callout)
        Button("Try Again") { updater.dismissError(); updater.checkNow() }.controlSize(.small)
      }
    }
  }

  @ViewBuilder private func notes(_ r: UpdateRelease) -> some View {
    let text = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
      DisclosureGroup("What's new") {
        let clipped = text.count > 1500 ? String(text.prefix(1500)) + "…" : text
        Text((try? AttributedString(markdown: clipped, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(clipped))
          .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
      }
    }
  }
}

/// A strip at the top of the menu pop-up while an update is waiting, downloading or ready.
public struct UpdateBanner: View {
  @ObservedObject var updater: Updater
  @MainActor public init(updater: Updater? = nil) { self.updater = updater ?? Updater.shared }

  public var body: some View {
    Group {
      switch updater.state {
      case .available(let r):
        row("arrow.down.circle.fill", "Kitbag \(r.versionText) is available", detail: nil) {
          Button("Update") { updater.installBlocker == nil ? updater.update() : updater.openReleasePage() }
        }
      case .downloading(let p):
        VStack(alignment: .leading, spacing: 6) {
          Text("Downloading update… \(Int(p * 100))%").font(.callout)
          ProgressView(value: p)
        }
      case .preparing:
        row("checkmark.shield", "Checking the download…", detail: nil) { ProgressView().controlSize(.small) }
      case .ready(let r):
        row("checkmark.seal.fill", "Kitbag \(r.versionText) is ready", detail: "Restarts in a few seconds") {
          Button("Restart") { updater.restart() }
        }
      case .installing:
        row("arrow.triangle.2.circlepath", "Restarting…", detail: nil) { ProgressView().controlSize(.small) }
      case .failed(let message) where updater.failedWhileUpdating:
        row("exclamationmark.triangle.fill", "Update failed", detail: message) {
          Button("Retry") { updater.dismissError(); updater.checkNow() }
        }
      default:
        EmptyView()
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.18)))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.4)))
  }

  private func row<Trailing: View>(_ symbol: String, _ title: String, detail: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.callout.weight(.semibold))
        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
      }
      Spacer(minLength: 4)
      trailing().controlSize(.small).buttonStyle(.borderedProminent)
    }
  }
}
