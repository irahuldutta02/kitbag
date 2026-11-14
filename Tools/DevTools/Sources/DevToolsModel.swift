import AppKit

@MainActor
final class DevToolsModel: ObservableObject {
  private var sampler: NSColorSampler?
  private var overlay: MeasureOverlay?
  private let popup = ResultPopup()
  var showsPopup = true  // tests turn this off

  // MARK: Color picker

  func pickColor() {
    let s = NSColorSampler()
    sampler = s
    s.show { [weak self] color in
      MainActor.assumeIsolated {
        self?.sampler = nil
        if let color { self?.finish(color) }
      }
    }
  }

  func finish(_ color: NSColor) {
    guard let v = ColorValue(color) else { return }
    copy(v.hex)
    if showsPopup { popup.show(.color(v)) { [weak self] in self?.copy($0) } }
  }

  // MARK: Measure

  func measure() {
    overlay?.cancel()
    let o = MeasureOverlay()
    overlay = o
    o.begin { [weak self] size, scale in
      guard let self else { return }
      self.overlay = nil
      guard let size else { return }
      let m = Measurement(points: size, scale: scale)
      self.copy(m.pointsText)
      if self.showsPopup { self.popup.show(.size(m)) { [weak self] in self?.copy($0) } }
    }
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func stop() {
    overlay?.cancel()
    overlay = nil
    sampler = nil
    popup.close()
  }
}
