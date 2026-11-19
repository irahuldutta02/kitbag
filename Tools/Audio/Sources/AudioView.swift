import CoreAudio
import KitbagCore
import SwiftUI

struct AudioView: View {
  @ObservedObject var model: AudioModel

  var body: some View {
    VStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 8) {
        DeviceSection(
          title: "Output",
          devices: model.outputs,
          selected: model.multiOutput ? model.selectedOutputs : [model.defaultOutput],
          multi: model.multiOutput,
          multiSwitch: Binding(get: { model.multiOutput }, set: { model.setMultiOutput($0) })
        ) { model.select($0, input: false) }

        Divider().opacity(0.45)

        DeviceSection(
          title: "Input",
          devices: model.inputs,
          selected: [model.defaultInput],
          multi: false,
          multiSwitch: nil
        ) { model.select($0, input: true) }

        Divider().opacity(0.45)

        Button(action: model.openSoundSettings) {
          HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(width: 24)
            Text("Sound Settings…")
              .font(.callout)
            Spacer()
            Image(systemName: "arrow.up.right")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.tertiary)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 6)
          .hoverHighlight(cornerRadius: 8)
          .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      .card(padding: 11)

      if let m = model.message {
        Label(m, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(KitbagUI.danger)
      }
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
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        SectionEyebrow(title)
        Spacer()
        if let multiSwitch {
          HStack(spacing: 5) {
            Text("Multi-Output").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Toggle("Multiple outputs", isOn: multiSwitch)
              .toggleStyle(.switch)
              .controlSize(.mini)
              .labelsHidden()
          }
        }
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 2)

      ForEach(devices) { d in
        let isOn = selected.contains(d.id)
        Button {
          pick(d)
        } label: {
          HStack(spacing: 10) {
            ZStack {
              Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1))
              Image(systemName: d.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
            }
            .frame(width: 26, height: 26)

            Text(d.name)
              .font(.callout.weight(isOn ? .medium : .regular))
              .lineLimit(1)

            Spacer(minLength: 4)

            if multi {
              Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
            } else if isOn {
              Image(systemName: "checkmark")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color.accentColor)
            }
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 5)
          .background(
            isOn ? Color.accentColor.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .hoverHighlight(cornerRadius: 8)
          .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isOn ? "\(d.name), selected" : d.name)
      }

      if devices.isEmpty {
        Text("No devices found")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
      }
    }
  }
}
