import SwiftUI

enum SettingsPalette {
    static let window = Color(red: 0.133, green: 0.133, blue: 0.18)
    static let text = Color(red: 0.87, green: 0.87, blue: 0.89)
    static let secondary = Color(red: 0.63, green: 0.64, blue: 0.68)
    static let accent = Color(red: 0.20, green: 0.80, blue: 0.73)
    static let border = Color.white.opacity(0.11)
    static let selection = Color(red: 0.63, green: 0.66, blue: 0.76).opacity(0.15)

    static let panel = LinearGradient(
        colors: [Color(red: 0.19, green: 0.21, blue: 0.24), Color(red: 0.17, green: 0.18, blue: 0.23)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13)
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.panel, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(SettingsPalette.border, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(SettingsPalette.border).frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(minHeight: 42)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var symbol: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(SettingsPalette.accent)
                }
                Text(title)
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(SettingsPalette.accent)
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    var showsPill = false

    var body: some View {
        SettingsRow {
            Text(title)
            Spacer(minLength: 8)
            if showsPill {
                SettingsValuePill(value: value)
            } else {
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsValuePill: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay { Capsule().strokeBorder(SettingsPalette.border, lineWidth: 1) }
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                Spacer()
                SettingsValuePill(value: level.formatted(.percent.precision(.fractionLength(0))))
            }
            .accessibilityHidden(true)
            Slider(value: $level, in: 0...1) { Text(title) }
                .labelsHidden()
                .tint(SettingsPalette.accent)
                .accessibilityLabel(title)
                .accessibilityValue(level.formatted(.percent.precision(.fractionLength(0))))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 14)
    }
}

struct SettingsGroupHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SettingsPalette.secondary)
            .padding(.leading, 7)
            .accessibilityAddTraits(.isHeader)
    }
}
