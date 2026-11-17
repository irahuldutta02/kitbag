import AppKit
import CoreImage
import SwiftUI

/// Makes a QR code picture. Everything happens on this Mac.
enum QRCode {
  static func image(for text: String, points: CGFloat = 260) -> NSImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let raw = filter.outputImage else { return nil }
    let scale = max(1, (points * 2 / raw.extent.width).rounded(.down))  // whole pixels per square keeps it sharp
    let big = raw.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: points, height: points))
  }
}

/// The window that shows an account as a QR code, to be scanned by another authenticator app. One at a time.
@MainActor
enum QRCodeWindow {
  private static var window: NSWindow?

  static func show(_ entry: AuthEntry) {
    let host = NSHostingController(rootView: QRCodeView(entry: entry, close: { close() }))
    let w =
      window
      ?? {
        let w = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 360, height: 600), styleMask: [.titled, .closable],
          backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.followActiveSpace()
        w.center()
        window = w
        return w
      }()
    w.title = String(localized: "Scan to Add Elsewhere")
    w.contentViewController = host
    w.setContentSize(NSSize(width: 360, height: 600))
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
  }

  static func close() {
    window?.orderOut(nil)
    window?.contentViewController = nil  // drop the secret as soon as it isn't needed
  }
}

private final class CopiedFlag: ObservableObject { @Published var copied = false }

private struct QRCodeView: View {
  let entry: AuthEntry
  let close: () -> Void
  @StateObject private var flag = CopiedFlag()

  var body: some View {
    VStack(spacing: 14) {
      VStack(spacing: 2) {
        Text(entry.primary).font(.headline)
        if let s = entry.secondary { Text(s).font(.callout).foregroundStyle(.secondary) }
      }
      if let image = QRCode.image(for: entry.uri) {
        Image(nsImage: image)
          .interpolation(.none).resizable().frame(width: 260, height: 260)
          .padding(14)
          .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))  // QR codes need a light background
          .accessibilityLabel("QR code for \(entry.primary)")
      } else {
        Text("Couldn't make a QR code for this account.").foregroundStyle(.red)
      }
      TimelineView(.periodic(from: .now, by: 1)) { ctx in
        VStack(spacing: 4) {
          HStack(spacing: 10) {
            Text(OTP.grouped(entry.code(at: ctx.date), kind: entry.kind))
              .font(.system(size: 26, weight: .semibold, design: .monospaced))
            CountdownRing(remaining: entry.remaining(at: ctx.date), period: entry.period)
          }
          Text("Code here now. After adding the account, check the other app shows the same code.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
      }
      Text("In the other authenticator app choose Add account ▸ Scan QR code, then point it at this window.")
        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      if entry.kind == .steam {
        Label("Steam Guard codes only work in apps that support Steam.", systemImage: "info.circle")
          .font(.caption).foregroundStyle(.secondary)
      }
      Label("Anyone who scans this can create your codes. Close it when you're done.", systemImage: "exclamationmark.triangle")
        .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.leading)
      Spacer(minLength: 0)
      HStack {
        Button(flag.copied ? "Link Copied" : "Copy Link") {
          let pb = NSPasteboard.general
          pb.clearContents()
          pb.setString(entry.uri, forType: .string)
          pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
          flag.copied = true
        }
        Spacer()
        Button("Done", action: close).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(width: 360, height: 600)
  }
}
