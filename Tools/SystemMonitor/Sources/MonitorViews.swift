import AppKit
import KitbagCore
import SwiftUI

private func bytes(_ v: UInt64, memory: Bool = false) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: memory ? .memory : .file)
}
private func rate(_ v: Double) -> String { bytes(UInt64(max(0, v))) + "/s" }
private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

struct MonitorView: View {
  @ObservedObject var model: MonitorModel

  var body: some View {
    VStack(spacing: 10) {
      if let s = model.snapshot {
        let memory = s.memoryTotal > 0 ? Double(s.memoryUsed) / Double(s.memoryTotal) : 0
        let storageUsed = s.storageTotal > 0 ? Double(s.storageUsed) / Double(s.storageTotal) : 0
        let storageFree = s.storageTotal >= s.storageUsed ? s.storageTotal - s.storageUsed : 0

        HStack(spacing: 8) {
          RingTile(
            title: "CPU",
            detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores",
            symbol: "cpu",
            fraction: s.cpu,
            tint: .blue,
            warn: s.cpu > 0.9,
            selected: model.expanded == .cpu
          ) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
              model.toggle(.cpu)
            }
          }
          RingTile(
            title: "Memory",
            detail: bytes(s.memoryUsed, memory: true),
            symbol: "memorychip",
            fraction: memory,
            tint: .purple,
            warn: memory > 0.9,
            selected: model.expanded == .memory
          ) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
              model.toggle(.memory)
            }
          }
          RingTile(
            title: "Storage",
            detail: "\(bytes(storageFree)) free",
            symbol: "internaldrive",
            fraction: storageUsed,
            tint: .orange,
            warn: storageUsed > 0.9,
            selected: false,
            action: nil
          )
        }

        if model.expanded != nil {
          ProcessList(model: model)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // Compact 2-column network throughput card
        HStack(spacing: 0) {
          NetworkStat(
            symbol: "arrow.down.circle.fill",
            tint: KitbagUI.success,
            title: "Download",
            value: rate(s.netDown)
          )
          Divider().frame(height: 28).opacity(0.5)
          NetworkStat(
            symbol: "arrow.up.circle.fill",
            tint: .orange,
            title: "Upload",
            value: rate(s.netUp)
          )
        }
        .card(padding: 10)

        if let b = s.battery { BatteryCard(battery: b) }

        if let n = model.notice {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(KitbagUI.danger)
            Text(n).font(.caption).foregroundStyle(KitbagUI.danger)
            Spacer(minLength: 4)
            Button {
              model.notice = nil
            } label: {
              Image(systemName: "xmark").font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(
            KitbagUI.danger.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
        }
      } else {
        VStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Reading system metrics…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .card()
      }
    }
  }
}

private struct RingTile: View {
  let title: LocalizedStringKey
  let detail: String
  let symbol: String
  let fraction: Double
  let tint: Color
  let warn: Bool
  let selected: Bool
  let action: (() -> Void)?

  private var color: Color { warn ? KitbagUI.danger : tint }

  private var content: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle().stroke(color.opacity(0.16), lineWidth: 6.5)
        Circle()
          .trim(from: 0, to: min(max(fraction, 0), 1))
          .stroke(color.gradient, style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.easeOut(duration: 0.35), value: fraction)
        Text(percent(fraction))
          .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
          .contentTransition(.numericText())
      }
      .frame(width: 54, height: 54)

      VStack(spacing: 1) {
        HStack(spacing: 3) {
          Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
          Text(title).font(.caption.weight(.semibold)).lineLimit(1)
        }
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
    }
    .frame(maxWidth: .infinity)
    .card(
      padding: 10,
      borderColor: selected ? color : nil,
      borderWidth: 1.5
    )
    .overlay(alignment: .topTrailing) {
      if action != nil {
        Image(systemName: selected ? "chevron.up" : "chevron.down")
          .font(.system(size: 8.5, weight: .bold))
          .foregroundStyle(selected ? color : .secondary)
          .padding(7)
      }
    }
    .hoverHighlight(cornerRadius: KitbagUI.cardRadius, tint: action != nil ? color : nil)
    .contentShape(RoundedRectangle(cornerRadius: KitbagUI.cardRadius, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  var body: some View {
    if let action {
      Button(action: action) { content }
        .buttonStyle(PressableStyle())
        .help(selected ? "Hide process breakdown" : "Show top processes")
    } else {
      content
    }
  }
}

private struct NetworkStat: View {
  let symbol: String
  let tint: Color
  let title: LocalizedStringKey
  let value: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 15))
        .foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        Text(value)
          .font(.callout.weight(.semibold).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

private struct BatteryCard: View {
  let battery: BatteryInfo

  private var symbol: String {
    if battery.charging { return "battery.100.bolt" }
    switch battery.percent {
    case ..<0.13: return "battery.0"
    case ..<0.38: return "battery.25"
    case ..<0.63: return "battery.50"
    case ..<0.88: return "battery.75"
    default: return "battery.100"
    }
  }

  private var barColor: Color {
    battery.percent < 0.2 ? KitbagUI.danger : KitbagUI.success
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(barColor)
        Text("Battery").font(.callout.weight(.semibold))
        if battery.charging || battery.onAC {
          Text(battery.charging ? "Charging" : "On AC")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(barColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(barColor.opacity(0.14), in: Capsule())
        }
        Spacer()
        Text(percent(battery.percent))
          .font(.callout.weight(.semibold).monospacedDigit())
      }

      // Sleek custom capsule battery gauge
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.primary.opacity(0.1))
          Capsule()
            .fill(barColor.gradient)
            .frame(width: max(6, geo.size.width * min(max(battery.percent, 0), 1)))
            .animation(.easeOut(duration: 0.3), value: battery.percent)
        }
      }
      .frame(height: 6)

      if let h = battery.health {
        HStack(spacing: 6) {
          Label("Health \(percent(h))", systemImage: "heart.fill")
            .foregroundStyle(.pink, .secondary)
          Spacer()
          if let cycles = battery.cycles {
            Text("\(cycles) cycles")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
        .font(.caption)
      }
    }
    .card(padding: 11)
    .accessibilityElement(children: .combine)
  }
}

private struct ProcessList: View {
  @ObservedObject var model: MonitorModel

  private func value(cpu: Double, memory: UInt64) -> String {
    model.expanded == .memory ? bytes(memory, memory: true) : String(format: "%.1f%%", cpu)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SectionEyebrow(model.expanded == .memory ? "Apps by Memory" : "Apps by CPU")
        Spacer()
        if !model.sortedGroups.isEmpty {
          Text("\(model.sortedGroups.count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      SearchFieldBar("Filter apps…", text: $model.query)

      if model.groups.isEmpty {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Sampling processes…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      } else if model.sortedGroups.isEmpty {
        Text("No matching apps")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(model.sortedGroups) { g in
              let open = model.openGroups.contains(g.id)
              let many = g.members.count > 1
              HStack(spacing: 7) {
                Button {
                  if many { model.toggleGroup(g.id) }
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                      .font(.system(size: 8.5, weight: .bold))
                      .foregroundStyle(.secondary)
                      .opacity(many ? 1 : 0)
                      .frame(width: 10)
                    icon(g).frame(width: 19, height: 19)
                    Text(g.name)
                      .font(.callout)
                      .lineLimit(1)
                      .truncationMode(.tail)
                    if many {
                      Text("×\(g.members.count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 4)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(many ? "\(g.name), \(g.members.count) processes" : g.name)

                Text(value(cpu: g.cpu, memory: g.memory))
                  .font(.caption.weight(.medium).monospacedDigit())
                  .foregroundStyle(.secondary)

                if g.isSelf {
                  Color.clear.frame(width: 18, height: 18)
                } else {
                  Button {
                    model.quit(g)
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.system(size: 13))
                      .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)
                  .hoverHighlight(cornerRadius: 9, tint: KitbagUI.danger)
                  .help("Quit \(g.name)")
                  .accessibilityLabel("Quit \(g.name)")
                }
              }
              .padding(.horizontal, 5)
              .padding(.vertical, 4)
              .hoverHighlight(cornerRadius: 7)

              if open {
                ForEach(model.members(of: g)) { e in
                  HStack(spacing: 7) {
                    Text(e.name).font(.caption).lineLimit(1).truncationMode(.middle)
                    Text("\(e.pid)")
                      .font(.caption2.monospacedDigit())
                      .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text(value(cpu: e.cpu, memory: e.memory))
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(.secondary)
                    Button {
                      model.quit(e)
                    } label: {
                      Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit process \(e.pid)")
                    .accessibilityLabel("Quit \(e.name) \(e.pid)")
                  }
                  .padding(.leading, 34)
                  .padding(.trailing, 5)
                  .padding(.vertical, 2.5)
                  .hoverHighlight(cornerRadius: 6)
                }
              }
            }
          }
          .padding(.trailing, 10)
        }
        .scrollIndicators(.visible)
        .frame(height: min(CGFloat(model.sortedGroups.count) * 30 + 8, 224))
      }
    }
    .card(padding: 11)
  }

  @ViewBuilder private func icon(_ g: ProcessGroup) -> some View {
    if let p = g.appPath {
      Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable()
    } else {
      Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
    }
  }
}

struct MonitorSettingsView: View {
  @ObservedObject var model: MonitorModel

  var body: some View {
    Picker("Refresh interval", selection: $model.interval) {
      ForEach(MonitorModel.intervals, id: \.self) { Text("\(Int($0)) s").tag($0) }
    }
  }
}
