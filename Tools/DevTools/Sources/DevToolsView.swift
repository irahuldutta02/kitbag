import AppKit
import KitbagCore
import SwiftUI

/// Just the launchers; results appear in a popup next to the cursor.
struct DevToolsView: View {
  @ObservedObject var model: DevToolsModel

  var body: some View {
    VStack(spacing: 10) {
      launcher("Pick Color", symbol: "eyedropper", action: model.pickColor)
      launcher("Measure Area", symbol: "ruler", action: model.measure)
    }
  }

  private func launcher(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.callout.weight(.medium))
        .frame(maxWidth: .infinity, minHeight: 56)
        .card()
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A label, a value and a copy button.
struct CopyRow: View {
  let title: LocalizedStringKey
  let value: String
  let copy: (String) -> Void

  var body: some View {
    HStack {
      Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
      Text(value).font(.callout.monospacedDigit()).textSelection(.enabled)
      Spacer(minLength: 4)
      Button {
        copy(value)
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.borderless).help("Copy")
      .accessibilityLabel("Copy \(value)")
    }
  }
}
