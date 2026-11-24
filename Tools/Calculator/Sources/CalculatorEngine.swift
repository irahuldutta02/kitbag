import Foundation

/// Evaluates simple arithmetic: + − × ÷ ^ %, parentheses, unary minus and decimals.
/// Written by hand (no NSExpression) so bad input returns nil instead of raising an exception.
enum CalculatorEngine {
  static func evaluate(_ text: String) -> Double? {
    var p = Parser(Array(normalize(text)))
    guard let v = p.expression(), p.atEnd, v.isFinite else { return nil }
    return v
  }

  static func normalize(_ s: String) -> String {
    s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
      .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "")
      .filter { !$0.isWhitespace }
  }

  /// Shows whole numbers without ".0" and trims float noise.
  static func format(_ v: Double) -> String {
    if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.usesGroupingSeparator = false
    f.maximumFractionDigits = 10
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
  }

  private struct Parser {
    let c: [Character]
    var i = 0
    init(_ c: [Character]) { self.c = c }
    var atEnd: Bool { i >= c.count }
    func peek() -> Character? { i < c.count ? c[i] : nil }

    mutating func expression() -> Double? {
      guard var v = term() else { return nil }
      while let ch = peek(), ch == "+" || ch == "-" {
        i += 1
        guard let r = term() else { return nil }
        v = ch == "+" ? v + r : v - r
      }
      return v
    }

    mutating func term() -> Double? {
      guard var v = power() else { return nil }
      while let ch = peek(), ch == "*" || ch == "/" {
        i += 1
        guard let r = power() else { return nil }
        if ch == "/" && r == 0 { return nil }
        v = ch == "*" ? v * r : v / r
      }
      return v
    }

    mutating func power() -> Double? {
      guard let base = unary() else { return nil }
      if peek() == "^" {
        i += 1
        guard let e = power() else { return nil }  // right associative
        return pow(base, e)
      }
      return base
    }

    mutating func unary() -> Double? {
      if peek() == "-" { i += 1; return unary().map { -$0 } }
      if peek() == "+" { i += 1; return unary() }
      return postfix()
    }

    mutating func postfix() -> Double? {
      guard var v = primary() else { return nil }
      while peek() == "%" { i += 1; v /= 100 }
      return v
    }

    mutating func primary() -> Double? {
      if peek() == "(" {
        i += 1
        guard let v = expression(), peek() == ")" else { return nil }
        i += 1
        return v
      }
      let start = i
      while let ch = peek(), ch.isNumber || ch == "." { i += 1 }
      guard i > start else { return nil }
      return Double(String(c[start..<i]))
    }
  }
}
