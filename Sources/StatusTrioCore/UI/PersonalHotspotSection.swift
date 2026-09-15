import SwiftUI

struct PersonalHotspotSection: View {
    @ObservedObject var controller: PersonalHotspotController
    @EnvironmentObject private var localization: Localization
    let currentSSID: String?
    let disabled: Bool

    var body: some View {
        if !controller.devices.isEmpty {
            Text(localization.string(.wifiPersonalHotspot))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(controller.devices) { device in
                Button {
                    controller.connect(device)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "personalhotspot")
                            .frame(width: 20)
                            .foregroundStyle(device.name == currentSSID ? Color.accentColor : .secondary)
                        Text(device.name).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        if controller.connectingID == device.id {
                            ProgressView().controlSize(.small)
                        } else {
                            if let signal = device.signal {
                                HStack(alignment: .bottom, spacing: 2) {
                                    ForEach(0..<4) { index in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(index < signal ? 0.65 : 0.18))
                                            .frame(width: 3, height: CGFloat(4 + index * 3))
                                    }
                                }
                                .accessibilityLabel("\(signal)/4")
                            }
                            if let cellular = device.cellular {
                                Text(cellular).font(.caption)
                            }
                            if let battery = device.battery {
                                Image(systemName: batterySymbol(battery))
                                    .help("\(battery)%")
                                    .accessibilityLabel("\(battery)%")
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled || controller.connectingID != nil || device.name == currentSSID)
            }
            if controller.failed {
                Text(localization.string(.wifiConnectionFailed)).font(.caption).foregroundStyle(.red)
            }
            Divider()
        }
    }

    private func batterySymbol(_ percentage: Int) -> String {
        switch percentage {
        case 0..<13: "battery.0percent"
        case 13..<38: "battery.25percent"
        case 38..<63: "battery.50percent"
        case 63..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
