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
      HStack(spacing: 8) {
        Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .foregroundStyle(toast.isError ? .red : .green)
        Text(m).font(.callout).lineLimit(3)
        Button { toast.hide() } label: { Image(systemName: "xmark") }
          .buttonStyle(.plain).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
      .shadow(radius: 8, y: 3)
      .padding(.bottom, 20)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}
