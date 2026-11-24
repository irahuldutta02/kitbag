import AppKit
import KitbagCore
import SwiftUI

struct PortManagerView: View {
  @ObservedObject var model: PortManagerModel

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        SearchFieldBar("Filter ports or apps", text: $model.filter)
        Button {
          Task { await model.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 7)
        .help("Refresh")
      }

      ScrollView {
        VStack(spacing: 8) {
          ForEach(model.groups) { g in groupCard(g) }
          otherPorts
        }
        .padding(.vertical, 1)
      }
      .scrollIndicators(.hidden)
      .frame(height: 330)  // fixed, so the window never changes size as ports come and go

      newGroupBar

      if let e = model.lastError {
        Text(e).font(.caption).foregroundStyle(KitbagUI.danger).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .onAppear {
      model.startPolling()
    }
    .onDisappear { model.stopPolling() }
  }

  // MARK: Groups

  private func groupCard(_ g: PortGroup) -> some View {
    let running = model.runningPIDs(in: g).count
    let live = g.ports.sorted().filter { !model.listeners(on: $0).isEmpty }
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(.teal)
        Text(g.name).font(.callout.weight(.semibold)).lineLimit(1)
        Text("\(live.count)")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(Color.primary.opacity(0.08), in: Capsule())
        Spacer(minLength: 4)
        Button {
          model.killGroup(g)
        } label: {
          Label("Kill all", systemImage: "bolt.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(running > 0 ? KitbagUI.danger : Color.secondary.opacity(0.5))
            .padding(.horizontal, 8).frame(height: 22)
            .background(
              (running > 0 ? KitbagUI.danger : Color.secondary).opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(running == 0)
        .help("Stop every process listening on this group's ports")
        Menu {
          Button("Rename…") {
            if let n = NamePrompt.ask(
              title: String(localized: "Rename group"), message: nil, current: g.name),
              !n.isEmpty
            { model.renameGroup(g, to: n) }
          }
          Button("Delete Group", role: .destructive) { model.deleteGroup(g) }
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 20, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
      }
      .padding(.bottom, live.isEmpty ? 0 : 6)

      if live.isEmpty {
        Text("Nothing running. Drag a port here, or use its ⋯ menu.")
          .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
      }
      // Only ports that are listening show up; one that stops (or is killed) leaves the list,
      // and comes back by itself if something starts on it again.
      ForEach(Array(live.enumerated()), id: \.element) { i, port in
        if i > 0 { Divider().opacity(0.4) }
        ForEach(model.listeners(on: port)) { row($0) }
      }
    }
    .card(padding: 10)
    .dropHighlight(model.dropTarget == g.id.uuidString)
    .dropDestination(for: String.self) { items, _ in model.drop(items, on: g) } isTargeted: {
      model.dropTarget = $0 ? g.id.uuidString : (model.dropTarget == g.id.uuidString ? nil : model.dropTarget)
    }
  }

  private var otherPorts: some View {
    let items = model.ungrouped
    return VStack(alignment: .leading, spacing: 0) {
      SectionEyebrow("Listening ports").padding(.bottom, 6)
      if items.isEmpty {
        Text(model.filter.isEmpty ? "Nothing is listening right now." : "No matches.")
          .font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity).padding(.vertical, 12)
      }
      ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
        if i > 0 { Divider().opacity(0.4) }
        row(p)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 10)
    .dropHighlight(model.dropTarget == PortManagerModel.otherTarget)
    .dropDestination(for: String.self) { items, _ in model.drop(items, on: nil) } isTargeted: {
      model.dropTarget = $0 ? PortManagerModel.otherTarget : (model.dropTarget == PortManagerModel.otherTarget ? nil : model.dropTarget)
    }
  }

  // MARK: Rows

  private func row(_ p: ListeningPort) -> some View {
    HStack(spacing: 10) {
      Text(String(p.port))
        .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.teal)
        .frame(width: 52, height: 22)
        .background(Color.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      VStack(alignment: .leading, spacing: 1) {
        let l = model.label(for: p)
        let custom = model.portNames[p.port] != nil
        Text(model.displayName(for: p)).font(.callout.weight(.medium)).lineLimit(1)
        Text("\(custom ? l.title + " · " : "")\(l.detail) · pid \(String(p.pid)) · \(p.address)")
          .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 4)
      Button {
        model.kill(pids: [p.pid])
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 15))
          .foregroundStyle(KitbagUI.danger.opacity(0.85))
          .frame(width: 22, height: 22)
      }
      .buttonStyle(.plain)
      .help("Stop this process")
      groupMenu(p.port)
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .draggable(PortManagerModel.dragPayload(p.port)) { dragPreview(p.port) }
  }

  private func idleRow(_ port: Int) -> some View {
    HStack(spacing: 10) {
      Text(String(port))
        .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 52, height: 22)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      Text(model.portNames[port] ?? "Free").font(.callout).foregroundStyle(model.portNames[port] == nil ? .tertiary : .secondary)
      Spacer(minLength: 4)
      groupMenu(port)
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .draggable(PortManagerModel.dragPayload(port)) { dragPreview(port) }
  }

  private func dragPreview(_ port: Int) -> some View {
    Text(String(port))
      .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 12).frame(height: 26)
      .background(Color.teal.gradient, in: Capsule())
  }

  private func groupMenu(_ port: Int) -> some View {
    let current = model.group(of: port)
    return Menu {
      ForEach(model.groups) { g in
        Button {
          model.assign(port: port, to: g)
        } label: {
          if g.id == current?.id { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
        }
      }
      if !model.groups.isEmpty { Divider() }
      if current != nil { Button("Remove from Group") { model.assign(port: port, to: nil) } }
      Button("Rename…") {
        if let n = NamePrompt.ask(
          title: String(localized: "Rename port \(String(port))"),
          message: String(localized: "Leave empty to use the app's own name."),
          current: model.portNames[port] ?? "")
        { model.setName(n, for: port) }
      }
      Button("Copy Port") { model.copy(String(port)) }
    } label: {
      Image(systemName: "ellipsis.circle").font(.system(size: 14)).frame(width: 22, height: 22)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Group")
  }

  private var newGroupBar: some View {
    HStack(spacing: 6) {
      Image(systemName: "folder.badge.plus").foregroundStyle(.secondary)
      TextField("New group name", text: $model.newGroupName)
        .textFieldStyle(.plain)
        .onSubmit { model.createGroupFromField() }
      Button("Add") { model.createGroupFromField() }
        .controlSize(.small)
        .disabled(model.newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    .padding(.horizontal, 10)
    .frame(height: 32)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
  }
}

private extension View {
  /// Ring around a card while a port is dragged over it.
  func dropHighlight(_ on: Bool) -> some View {
    overlay(
      RoundedRectangle(cornerRadius: KitbagUI.cardRadius, style: .continuous)
        .strokeBorder(Color.teal, lineWidth: on ? 2 : 0)
        .background(
          RoundedRectangle(cornerRadius: KitbagUI.cardRadius, style: .continuous)
            .fill(Color.teal.opacity(on ? 0.08 : 0))
        )
        .allowsHitTesting(false)
    )
  }
}

/// A small "type a name" dialog.
@MainActor enum NamePrompt {
  /// Returns the typed text, or nil if cancelled.
  static func ask(title: String, message: String?, current: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    if let message { alert.informativeText = message }
    alert.addButton(withTitle: String(localized: "Save"))
    alert.addButton(withTitle: String(localized: "Cancel"))
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = current
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
  }
}
