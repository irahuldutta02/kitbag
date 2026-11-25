import SwiftUI

/// Brand marks for the AI providers, drawn as vector paths (no bundled assets).
/// Claude and OpenAI marks: simple-icons (CC0). Antigravity: the arch from
/// lobe-icons (MIT), colored like its published logo.
struct LogoShape: Shape {
  let commands: String
  let box: CGSize

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / box.width, rect.height / box.height)
    let dx = rect.minX + (rect.width - box.width * scale) / 2
    let dy = rect.minY + (rect.height - box.height * scale) / 2
    func pt(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(x: dx + CGFloat(x) * scale, y: dy + CGFloat(y) * scale)
    }
    var path = Path()
    let parts = commands.split(separator: " ")
    var i = 0
    func n() -> Double { defer { i += 1 }; return Double(parts[i]) ?? 0 }
    while i < parts.count {
      let c = parts[i]; i += 1
      switch c {
      case "M": path.move(to: pt(n(), n()))
      case "L": path.addLine(to: pt(n(), n()))
      case "C":
        let a = pt(n(), n()), b = pt(n(), n()), e = pt(n(), n())
        path.addCurve(to: e, control1: a, control2: b)
      case "Z": path.closeSubpath()
      default: break
      }
    }
    return path
  }
}

enum ProviderLogoData {
  static let claude = "M 4.7144 15.9555 L 9.4318 13.3084 L 9.5108 13.0777 L 9.4318 12.9502 L 9.2011 12.9502 L 8.4118 12.9016 L 5.7162 12.8287 L 3.3787 12.7316 L 1.1141 12.6102 L 0.5434 12.4887 L 0.0091 11.7845 L 0.0637 11.4323 L 0.5434 11.1105 L 1.2294 11.1713 L 2.7473 11.2745 L 5.0240 11.4323 L 6.6754 11.5295 L 9.1222 11.7845 L 9.5108 11.7845 L 9.5654 11.6266 L 9.4318 11.5295 L 9.3286 11.4323 L 6.9730 9.8356 L 4.4230 8.1477 L 3.0874 7.1763 L 2.3649 6.6845 L 2.0006 6.2231 L 1.8428 5.2153 L 2.4985 4.4928 L 3.3788 4.5535 L 3.6034 4.6142 L 4.4959 5.3002 L 6.4023 6.7756 L 8.8916 8.6092 L 9.2559 8.9127 L 9.4016 8.8095 L 9.4198 8.7367 L 9.2558 8.4634 L 7.9019 6.0167 L 6.4569 3.5274 L 5.8134 2.4954 L 5.6434 1.8760 C 5.5827 1.6210 5.5402 1.4086 5.5402 1.1475 L 6.2870 0.1335 L 6.6997 0.0000 L 7.6954 0.1336 L 8.1144 0.4978 L 8.7336 1.9125 L 9.7354 4.1407 L 11.2897 7.1703 L 11.7450 8.0688 L 11.9879 8.9006 L 12.0789 9.1556 L 12.2368 9.1556 L 12.2368 9.0099 L 12.3643 7.3039 L 12.6011 5.2092 L 12.8318 2.5135 L 12.9107 1.7546 L 13.2871 0.8439 L 14.0339 0.3521 L 14.6167 0.6314 L 15.0964 1.3174 L 15.0296 1.7607 L 14.7443 3.6124 L 14.1857 6.5145 L 13.8214 8.4574 L 14.0339 8.4574 L 14.2768 8.2145 L 15.2603 6.9092 L 16.9117 4.8449 L 17.6403 4.0253 L 18.4903 3.1207 L 19.0367 2.6896 L 20.0688 2.6896 L 20.8278 3.8189 L 20.4878 4.9846 L 19.4253 6.3324 L 18.5449 7.4738 L 17.2821 9.1738 L 16.4928 10.5338 L 16.5657 10.6431 L 16.7539 10.6248 L 19.6074 10.0178 L 21.1495 9.7384 L 22.9891 9.4227 L 23.8209 9.8113 L 23.9119 10.2059 L 23.5841 11.0134 L 21.6171 11.4991 L 19.3099 11.9605 L 15.8735 12.7741 L 15.8310 12.8045 L 15.8796 12.8652 L 17.4278 13.0109 L 18.0896 13.0473 L 19.7106 13.0473 L 22.7281 13.2720 L 23.5173 13.7940 L 23.9909 14.4316 L 23.9119 14.9173 L 22.6977 15.5366 L 21.0584 15.1480 L 17.2334 14.2373 L 15.9221 13.9094 L 15.7399 13.9094 L 15.7399 14.0187 L 16.8328 15.0873 L 18.8363 16.8965 L 21.3438 19.2279 L 21.4713 19.8047 L 21.1495 20.2601 L 20.8095 20.2115 L 18.6056 18.5540 L 17.7556 17.8072 L 15.8310 16.1862 L 15.7035 16.1862 L 15.7035 16.3562 L 16.1467 17.0058 L 18.4903 20.5272 L 18.6117 21.6079 L 18.4417 21.9600 L 17.8346 22.1725 L 17.1667 22.0511 L 15.7946 20.1265 L 14.3800 17.9590 L 13.2386 16.0162 L 13.0989 16.0952 L 12.4249 23.3504 L 12.1093 23.7207 L 11.3807 24.0000 L 10.7736 23.5386 L 10.4518 22.7918 L 10.7736 21.3165 L 11.1622 19.3919 L 11.4779 17.8619 L 11.7632 15.9615 L 11.9332 15.3301 L 11.9211 15.2876 L 11.7814 15.3058 L 10.3486 17.2730 L 8.1690 20.2176 L 6.4447 22.0632 L 6.0319 22.2272 L 5.3155 21.8568 L 5.3822 21.1950 L 5.7830 20.6061 L 8.1690 17.5704 L 9.6079 15.6884 L 10.5369 14.6016 L 10.5307 14.4437 L 10.4761 14.4437 L 4.1376 18.5601 L 3.0083 18.7058 L 2.5226 18.2504 L 2.5834 17.5037 L 2.8141 17.2608 L 4.7205 15.9494 Z"
  static let openai = "M 22.2819 9.8211 C 22.8248 8.1862 22.6369 6.3967 21.7662 4.9103 C 20.4571 2.6316 17.8260 1.4595 15.2564 2.0103 C 13.8083 0.3995 11.6112 -0.3168 9.4920 0.1311 C 7.3728 0.5789 5.6533 2.1229 4.9807 4.1818 C 3.2928 4.5279 1.8360 5.5847 0.9830 7.0818 C -0.3404 9.3568 -0.0401 12.2267 1.7257 14.1784 C 1.1808 15.8125 1.3670 17.6022 2.2367 19.0891 C 3.5475 21.3686 6.1803 22.5406 8.7513 21.9892 C 9.8948 23.2770 11.5377 24.0097 13.2599 24.0000 C 15.8937 24.0024 18.2271 22.3021 19.0317 19.7942 C 20.7194 19.4475 22.1760 18.3908 23.0294 16.8941 C 24.3368 14.6231 24.0351 11.7688 22.2819 9.8212 Z M 13.2599 22.4292 C 12.2086 22.4309 11.1903 22.0624 10.3835 21.3884 L 10.5254 21.3080 L 15.3037 18.5498 C 15.5456 18.4079 15.6949 18.1490 15.6964 17.8685 L 15.6964 11.1316 L 17.7164 12.3002 C 17.7367 12.3105 17.7508 12.3298 17.7544 12.3522 L 17.7544 17.9348 C 17.7491 20.4148 15.7399 22.4240 13.2599 22.4292 Z M 3.5992 18.3038 C 3.0720 17.3934 2.8827 16.3263 3.0646 15.2901 L 3.2066 15.3753 L 7.9896 18.1335 C 8.2306 18.2749 8.5292 18.2749 8.7702 18.1335 L 14.6130 14.7650 L 14.6130 17.0974 C 14.6119 17.1219 14.5997 17.1445 14.5798 17.1589 L 9.7400 19.9502 C 7.5893 21.1891 4.8416 20.4525 3.5992 18.3038 Z M 2.3408 7.8956 C 2.8717 6.9794 3.7096 6.2805 4.7063 5.9228 L 4.7063 11.6000 C 4.7026 11.8793 4.8513 12.1386 5.0942 12.2765 L 10.9086 15.6308 L 8.8885 16.7993 C 8.8663 16.8111 8.8397 16.8111 8.8175 16.7993 L 3.9872 14.0128 C 1.8408 12.7686 1.1047 10.0230 2.3408 7.8720 Z M 18.9371 11.7514 L 13.1038 8.3640 L 15.1192 7.2000 C 15.1414 7.1882 15.1680 7.1882 15.1902 7.2000 L 20.0205 9.9913 C 21.5281 10.8612 22.3979 12.5234 22.2531 14.2580 C 22.1083 15.9926 20.9750 17.4876 19.3440 18.0955 L 19.3440 12.4183 C 19.3355 12.1397 19.1808 11.8863 18.9370 11.7513 Z M 20.9478 8.7283 L 20.8058 8.6431 L 16.0323 5.8613 C 15.7898 5.7190 15.4894 5.7190 15.2469 5.8613 L 9.4090 9.2297 L 9.4090 6.8974 C 9.4065 6.8732 9.4174 6.8496 9.4374 6.8359 L 14.2677 4.0493 C 15.7790 3.1787 17.6573 3.2599 19.0877 4.2578 C 20.5182 5.2556 21.2431 6.9903 20.9479 8.7093 Z M 8.3065 12.8630 L 6.2865 11.6992 C 6.2660 11.6869 6.2521 11.6661 6.2485 11.6425 L 6.2485 6.0742 C 6.2508 4.3304 7.2605 2.7449 8.8397 2.0054 C 10.4190 1.2659 12.2833 1.5056 13.6242 2.6205 L 13.4822 2.7010 L 8.7040 5.4590 C 8.4621 5.6009 8.3128 5.8598 8.3113 6.1403 Z M 9.4041 10.4976 L 12.0061 8.9978 L 14.6130 10.4976 L 14.6130 13.4970 L 12.0156 14.9967 L 9.4089 13.4970 Z"
  static let antigravity =
    "M 21.751 22.607 C 23.091 23.612 25.101 22.942 23.259 21.099 C 17.73 15.74 18.904 1 12.037 1 C 5.17 1 6.342 15.74 0.815 21.1 C -1.195 23.109 0.982 23.611 2.322 22.606 C 7.514 19.089 7.179 12.892 12.037 12.892 C 16.894 12.892 16.559 19.089 21.751 22.607 Z"
}

/// The provider's real logo on a rounded tile.
struct ProviderLogo: View {
  let id: AIProviderID
  var size: CGFloat = 30

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(tile)
      mark.padding(size * 0.2)
    }
    .frame(width: size, height: size)
    .overlay(
      RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
  }

  private var tile: Color {
    switch id {
    case .codex: return .black
    case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
    case .antigravity: return .white
    }
  }

  @ViewBuilder private var mark: some View {
    switch id {
    case .codex:
      LogoShape(commands: ProviderLogoData.openai, box: CGSize(width: 24, height: 24))
        .fill(.white, style: FillStyle(eoFill: true))
    case .claude:
      LogoShape(commands: ProviderLogoData.claude, box: CGSize(width: 24, height: 24))
        .fill(.white)
    case .antigravity:
      AntigravityMark()
    }
  }
}

/// Antigravity's arch: blue at the feet, blending through green and yellow into red at the peak.
private struct AntigravityMark: View {
  var body: some View {
    GeometryReader { g in
      let side = min(g.size.width, g.size.height)
      ZStack {
        Color(red: 0.19, green: 0.53, blue: 1.0)
        glow(Color(red: 0.0, green: 0.73, blue: 0.36), x: 0.24, y: 0.36, radius: 0.42 * side)
        glow(Color(red: 1.0, green: 0.83, blue: 0.05), x: 0.40, y: 0.10, radius: 0.36 * side)
        glow(Color(red: 0.99, green: 0.25, blue: 0.24), x: 0.65, y: 0.10, radius: 0.46 * side)
      }
      .mask(LogoShape(commands: ProviderLogoData.antigravity, box: CGSize(width: 24, height: 24)))
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private func glow(_ color: Color, x: CGFloat, y: CGFloat, radius: CGFloat) -> some View {
    RadialGradient(
      stops: [
        .init(color: color, location: 0), .init(color: color.opacity(0.8), location: 0.35),
        .init(color: color.opacity(0), location: 1),
      ], center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: radius)
  }
}
