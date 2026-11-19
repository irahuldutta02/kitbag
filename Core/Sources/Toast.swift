import SwiftUI

/// A short message shown at the bottom of the Settings window: a success or a failure.
@MainActor
public final class Toast: ObservableObject {
  public static let shared = Toast()
  @Published public private(set) var message: String?
  @Published public private(set) var isError = false
  private var generation = 0

  public func show(_ text: String, error: Bool = false) {
    generation += 1
    let mine = generation
    message = text
    isError = error
    Task {
      try? await Task.sleep(nanoseconds: error ? 6_000_000_000 : 3_500_000_000)
      if mine == generation { message = nil }
    }
  }

  public func hide() { message = nil }
}

public struct ToastOverlay: View {
  @ObservedObject private var toast = Toast.shared
  public init() {}

  public var body: some View {
    if let m = toast.message {
      HStack(spacing: 9) {
        Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(toast.isError ? KitbagUI.danger : KitbagUI.success)
        Text(m)
          .font(.callout.weight(.medium))
          .lineLimit(3)
        Button {
          toast.hide()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .capsuleHoverHighlight()
      }
      .padding(.leading, 14)
      .padding(.trailing, 10)
      .padding(.vertical, 9)
      .glass(Capsule())
      .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
      .padding(.bottom, 20)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}
