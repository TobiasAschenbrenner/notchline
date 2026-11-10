import SwiftUI

struct LevelSettings: View {
    let section: SettingsSection
    @Binding var alertsEnabled: Bool
    let level: Binding<Double>?
    let output: SoundOutput?
    let usesNotchlineIndicators: Bool
    let allowKeyboardControls: () -> Void
    let controlError: String?

    var body: some View {
        let isDisplay = section == .display
        SettingsCard {
            SettingsToggleRow(
                title: isDisplay ? "Brightness alerts" : "Volume alerts",
                symbol: section.symbol,
                isOn: $alertsEnabled
            )
            if !isDisplay {
                SettingsDivider()
                SettingsValueRow(title: "Audio output", value: output?.routeName ?? "Unavailable")
            }
            SettingsDivider()
            let levelTitle = isDisplay ? "Brightness" : "Output volume"
            if let level {
                SettingsSliderRow(title: levelTitle, level: level)
            } else {
                SettingsValueRow(title: levelTitle, value: "Unavailable")
            }
            if alertsEnabled {
                SettingsDivider()
                SettingsValueRow(title: "Keyboard indicators", value: usesNotchlineIndicators ? "Notchline" : "macOS")
                if !usesNotchlineIndicators {
                    SettingsDivider()
                    SettingsRow {
                        Button("Allow Keyboard Controls…", action: allowKeyboardControls)
                            .help("Grant Accessibility access to show these keyboard indicators in Notchline.")
                    }
                }
            }
            if let controlError {
                SettingsDivider()
                SettingsRow {
                    Text(controlError)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsPalette.secondary)
                }
            }
        }
        SettingsGroupHeading(title: "Preview")
            .padding(.top, 7)
        if isDisplay {
            SettingsAlertPreview(alert: .brightness(level?.wrappedValue ?? 0.64), caption: "Brightness indicator")
        } else {
            SettingsAlertPreview(
                alert: .volume(level?.wrappedValue ?? 0.44, muted: output?.muted ?? false),
                caption: "Volume indicator",
                output: output
            )
        }
    }
}
