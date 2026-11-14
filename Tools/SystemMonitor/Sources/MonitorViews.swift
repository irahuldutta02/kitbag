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
        let free =
          s.storageTotal > 0 ? Double(s.storageTotal - s.storageUsed) / Double(s.storageTotal) : 0
        HStack(spacing: 8) {
          RingTile(
            title: "CPU", detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores",
            symbol: "cpu", fraction: s.cpu, tint: .blue, warn: s.cpu > 0.9,
            selected: model.expanded == .cpu
          ) { model.toggle(.cpu) }
          RingTile(
            title: "Memory", detail: "\(bytes(s.memoryUsed, memory: true))", symbol: "memorychip",
            fraction: memory, tint: .purple, warn: memory > 0.9, selected: model.expanded == .memory
          ) { model.toggle(.memory) }
          RingTile(
            title: "Free", detail: "\(bytes(s.storageTotal - s.storageUsed)) free",
            symbol: "internaldrive", fraction: free, tint: .orange, warn: free < 0.1,
            selected: false, action: nil)
        }
        if model.expanded != nil { ProcessList(model: model) }
        VStack(spacing: 8) {
          StatRow(
            symbol: "arrow.down.circle.fill", tint: .green, title: "Download",
            value: rate(s.netDown))
          StatRow(
            symbol: "arrow.up.circle.fill", tint: .orange, title: "Upload", value: rate(s.netUp))
        }
        .card()
        if let b = s.battery { BatteryCard(battery: b) }
        if let n = model.notice { Text(n).font(.caption).foregroundStyle(.red) }
      } else {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
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

  private var color: Color { warn ? .red : tint }

  private var content: some View {
    VStack(spacing: 4) {
      ZStack {
        Circle().stroke(color.opacity(0.18), lineWidth: 7)
        Circle().trim(from: 0, to: min(max(fraction, 0), 1))
          .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.smooth(duration: 0.6), value: fraction)
        Text(percent(fraction)).font(.system(.callout, design: .rounded).bold().monospacedDigit())
          .contentTransition(.numericText())
          .animation(.smooth, value: fraction)
      }
      .frame(width: 58, height: 58)
      Label(title, systemImage: symbol).font(.caption.bold()).labelStyle(.titleAndIcon)
      Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .card()
    .overlay(alignment: .topTrailing) {
      if action != nil {
        Image(systemName: selected ? "chevron.up" : "chevron.down")
          .font(.caption2.bold()).foregroundStyle(.secondary).padding(6)
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: 12).strokeBorder(tint, lineWidth: selected ? 1.5 : 0)
    )
    .accessibilityElement(children: .combine)
  }

  var body: some View {
    if let action {
      Button(action: action) { content }.buttonStyle(PressableStyle())
    } else {
      content
    }
  }
}

private struct StatRow: View {
  let symbol: String
  let tint: Color
  let title: LocalizedStringKey
  let value: String

  var body: some View {
    HStack {
      Label(title, systemImage: symbol).foregroundStyle(tint, .primary).font(.subheadline)
      Spacer()
      Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
    }
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

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Battery", systemImage: symbol).font(.subheadline.bold())
        Spacer()
        Text(
          percent(battery.percent)
            + (battery.charging ? " · Charging" : battery.onAC ? " · On AC" : "")
        )
        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
      }
      ProgressView(value: min(max(battery.percent, 0), 1)).tint(
        battery.percent < 0.2 ? .red : .green)
      if let h = battery.health {
        HStack {
          Label("Health", systemImage: "heart.fill").foregroundStyle(.pink, .primary)
          Spacer()
          Text(percent(h) + (battery.cycles.map { " · \($0) cycles" } ?? ""))
            .monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.caption)
      }
    }
    .card()
    .accessibilityElement(children: .combine)
  }
}

private struct ProcessList: View {
  @ObservedObject var model: MonitorModel

  private func value(cpu: Double, memory: UInt64) -> String {
    model.expanded == .memory ? bytes(memory, memory: true) : String(format: "%.1f%%", cpu)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.expanded == .memory ? "Apps by memory" : "Apps by CPU")
        .font(.caption.bold()).foregroundStyle(.secondary)
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search apps", text: $model.query).textFieldStyle(.plain)
        if !model.query.isEmpty {
          Button {
            model.query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
        }
      }
      .padding(.horizontal, 8).padding(.vertical, 5)
      .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
      if model.groups.isEmpty {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
      } else if model.sortedGroups.isEmpty {
        Text("No matching apps").font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(model.sortedGroups) { g in
            let open = model.openGroups.contains(g.id)
            let many = g.members.count > 1
            HStack(spacing: 8) {
              Button {
                if many { model.toggleGroup(g.id) }
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: many ? (open ? "chevron.down" : "chevron.right") : "circle")
                    .font(.caption2).opacity(many ? 1 : 0).frame(width: 10)
                  icon(g).frame(width: 20, height: 20)
                  Text(g.name).lineLimit(1).truncationMode(.tail)
                  if many {
                    Text("×\(g.members.count)").font(.caption2.bold()).foregroundStyle(.secondary)
                      .padding(.horizontal, 5).background(.quaternary, in: Capsule())
                  }
                  Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel(many ? "\(g.name), \(g.members.count) processes" : g.name)
              Text(value(cpu: g.cpu, memory: g.memory))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
              if g.isSelf {
                Color.clear.frame(width: 18, height: 18)  // Kitbag is listed; quit it from the menu
              } else {
                Button {
                  model.quit(g)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless).help("Quit all")
                .accessibilityLabel("Quit \(g.name)")
              }
            }
            if open {
              ForEach(model.members(of: g)) { e in
                HStack(spacing: 8) {
                  Text(e.name).font(.caption).lineLimit(1).truncationMode(.middle)
                  Text("\(e.pid)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                  Spacer(minLength: 4)
                  Text(value(cpu: e.cpu, memory: e.memory))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                  Button {
                    model.quit(e)
                  } label: {
                    Image(systemName: "xmark.circle")
                  }
                  .buttonStyle(.borderless).help("Quit this process")
                  .accessibilityLabel("Quit \(e.name) \(e.pid)")
                }
                .padding(.leading, 38)
              }
            }
          }
        }
        .padding(.trailing, 14)  // keeps the scroll bar off the Quit buttons
      }
      .scrollIndicators(.visible)
      .frame(height: 240)
    }
    .card()
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
