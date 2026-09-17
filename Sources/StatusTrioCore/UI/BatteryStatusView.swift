import SwiftUI

struct BatteryStatusView: View {
    @EnvironmentObject private var localization: Localization
    let battery: BatteryStatus
    let onOpenDetails: () -> Void
    let onOpenBatterySettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenDetails) {
                HStack(spacing: 10) {
                    Image(systemName: "battery.100")
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(StatusPresentation.batteryTitle(battery, localization: localization))
                            .font(.headline)
                            .monospacedDigit()
                        Text(StatusPresentation.batterySubtitle(battery, localization: localization))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localization.string(.batteryActionOpenDetails))

            if battery.isPresent {
                Button(
                    localization.string(.batteryActionOpenSettings),
                    systemImage: "gearshape",
                    action: onOpenBatterySettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.batteryActionOpenSettings))
                .accessibilityLabel(localization.string(.batteryActionOpenSettings))
                .frame(width: 24, height: 24)
            }
        }
    }
}
