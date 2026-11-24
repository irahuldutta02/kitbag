import KitbagCore
import SwiftUI

struct CalculatorView: View {
  @ObservedObject var model: CalculatorModel
  @FocusState private var focused: Bool

  private let rows: [[(String, String)]] = [
    [("C", "clear"), ("(", "("), (")", ")"), ("÷", "÷")],
    [("7", "7"), ("8", "8"), ("9", "9"), ("×", "×")],
    [("4", "4"), ("5", "5"), ("6", "6"), ("−", "-")],
    [("1", "1"), ("2", "2"), ("3", "3"), ("+", "+")],
    [("0", "0"), (".", "."), ("%", "%"), ("=", "equals")],
  ]

  var body: some View {
    VStack(spacing: 10) {
      VStack(alignment: .trailing, spacing: 2) {
        Text(model.expression.isEmpty ? "0" : model.expression)
          .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .foregroundStyle(model.expression.isEmpty ? .tertiary : .primary)
        Text(model.preview.map { "= \($0)" } ?? " ")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.horizontal, 12)
      .frame(height: 72)
      .card(padding: 0)
      .contextMenu { Button("Copy") { model.copyResult() } }

      VStack(spacing: 6) {
        ForEach(rows.indices, id: \.self) { r in
          HStack(spacing: 6) {
            ForEach(rows[r], id: \.1) { label, action in key(label, action) }
          }
        }
      }

      // Always three rows tall, so the window doesn't grow after the first calculation.
      VStack(alignment: .leading, spacing: 3) {
        SectionEyebrow("History")
        ForEach(0..<3, id: \.self) { i in
          if i < model.history.count {
            let h = model.history[i]
            Button { model.recall(h.result) } label: {
              HStack {
                Text(h.expression).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Text(h.result).fontWeight(.medium)
              }
              .font(.caption.monospacedDigit())
              .frame(height: 16)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          } else {
            Text(i == 0 ? "No calculations yet" : " ")
              .font(.caption)
              .foregroundStyle(.tertiary)
              .frame(height: 16, alignment: .leading)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
    .frame(width: 252)
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onAppear { focused = true }
    .onKeyPress(phases: .down) { press in handle(press) }
  }

  private func key(_ label: String, _ action: String) -> some View {
    let isOp = ["÷", "×", "−", "+"].contains(label)
    let isEq = action == "equals"
    let fill: AnyShapeStyle =
      isEq
      ? AnyShapeStyle(Color.accentColor.gradient)
      : AnyShapeStyle(isOp ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
    return Button {
      switch action {
      case "clear": model.clear()
      case "equals": model.equals()
      default: model.input(action)
      }
    } label: {
      Text(label)
        .font(.system(size: 17, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, minHeight: 38)
        .foregroundStyle(isEq ? Color.white : (isOp ? Color.accentColor : Color.primary))
        .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(isEq ? 0 : 0.07), lineWidth: 0.5))
    }
    .buttonStyle(PressableStyle())
  }

  private func handle(_ press: KeyPress) -> KeyPress.Result {
    switch press.key {
    case .return: model.equals(); return .handled
    case .delete: model.backspace(); return .handled
    case .escape: model.clear(); return .handled
    default: break
    }
    if press.modifiers.contains(.command) { return .ignored }  // leave ⌘C, ⌘W etc. alone
    let allowed = Set("0123456789.+-*/×÷−()%^")
    let s = press.characters
    guard !s.isEmpty, s.allSatisfy({ allowed.contains($0) }) else {
      if s == "=" { model.equals(); return .handled }
      return .ignored
    }
    model.input(s)
    return .handled
  }
}
