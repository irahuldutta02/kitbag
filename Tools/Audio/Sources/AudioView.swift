import CoreAudio
import KitbagCore
import SwiftUI

struct AudioView: View {
  @ObservedObject var model: AudioModel

  var body: some View {
    VStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        DeviceSection(
          title: "Output", devices: model.outputs,
          selected: model.multiOutput ? model.selectedOutputs : [model.defaultOutput],
          multi: model.multiOutput,
          multiSwitch: Binding(get: { model.multiOutput }, set: { model.setMultiOutput($0) })
        ) { model.select($0, input: false) }
        Divider()
        DeviceSection(
          title: "Input", devices: model.inputs, selected: [model.defaultInput], multi: false,
          multiSwitch: nil
        ) { model.select($0, input: true) }
        Divider()
        Button(action: model.openSoundSettings) {
          Text("Sound Settings…").frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .card()
      if let m = model.message { Text(m).font(.caption).foregroundStyle(.red) }
    }
  }
}

private struct DeviceSection: View {
  let title: LocalizedStringKey
  let devices: [AudioDevice]
  let selected: Set<UInt32>
  let multi: Bool
  let multiSwitch: Binding<Bool>?
  let pick: (AudioDevice) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.caption.bold()).foregroundStyle(.secondary)
        Spacer()
        if let multiSwitch {
          Text("Multiple").font(.caption).foregroundStyle(.secondary)
          Toggle("Multiple outputs", isOn: multiSwitch).toggleStyle(.switch).controlSize(.mini)
            .labelsHidden()
        }
      }
      ForEach(devices) { d in
        Button {
          pick(d)
        } label: {
          HStack(spacing: 10) {
            ZStack {
              Circle().fill(
                selected.contains(d.id) ? Color.accentColor : Color.secondary.opacity(0.35))
              Image(systemName: d.symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected.contains(d.id) ? Color.white : Color.primary)
            }
            .frame(width: 24, height: 24)
            Text(d.name).lineLimit(1)
            Spacer(minLength: 4)
            if multi {
              Image(systemName: selected.contains(d.id) ? "checkmark.square.fill" : "square")
                .foregroundStyle(selected.contains(d.id) ? Color.accentColor : .secondary)
            } else if selected.contains(d.id) {
              Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(
                Color.accentColor)
            }
          }
          .padding(.vertical, 2)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected.contains(d.id) ? "\(d.name), selected" : d.name)
      }
      if devices.isEmpty { Text("None").font(.caption).foregroundStyle(.secondary) }
    }
  }
}
