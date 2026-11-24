import SwiftUI

@MainActor
final class CalculatorModel: ObservableObject {
  @Published var expression = ""
  /// Finished calculations, newest first.
  @Published private(set) var history: [(expression: String, result: String)] = []

  /// Live answer while typing; nil when the expression isn't complete yet.
  var preview: String? {
    guard !expression.isEmpty, let v = CalculatorEngine.evaluate(expression) else { return nil }
    let s = CalculatorEngine.format(v)
    return s == expression ? nil : s
  }

  func input(_ s: String) { expression += s }
  func backspace() { if !expression.isEmpty { expression.removeLast() } }
  func clear() { expression = "" }

  func equals() {
    guard let v = CalculatorEngine.evaluate(expression) else { return }
    let result = CalculatorEngine.format(v)
    history.insert((expression, result), at: 0)
    if history.count > 20 { history.removeLast() }
    expression = result
  }

  func recall(_ result: String) { expression = result }

  func copyResult() {
    let text = preview ?? expression
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
