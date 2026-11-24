import Testing

@testable import Calculator

@MainActor @Suite struct CalculatorTests {
  @Test func arithmeticAndPrecedence() {
    #expect(CalculatorEngine.evaluate("2+3×4") == 14)
    #expect(CalculatorEngine.evaluate("(2+3)*4") == 20)
    #expect(CalculatorEngine.evaluate("2^3^2") == 512)
    #expect(CalculatorEngine.evaluate("-5+2") == -3)
    #expect(CalculatorEngine.evaluate("50%") == 0.5)
  }

  @Test func badInputIsNil() {
    #expect(CalculatorEngine.evaluate("") == nil)
    #expect(CalculatorEngine.evaluate("2+") == nil)
    #expect(CalculatorEngine.evaluate("1÷0") == nil)
    #expect(CalculatorEngine.evaluate("(2") == nil)
  }

  @Test func formatting() {
    #expect(CalculatorEngine.format(14) == "14")
    #expect(CalculatorEngine.format(0.1 + 0.2) == "0.3")
  }

  @Test func equalsStoresHistory() {
    let m = CalculatorModel()
    m.input("6×7")
    m.equals()
    #expect(m.expression == "42")
    #expect(m.history.first?.result == "42")
  }
}
