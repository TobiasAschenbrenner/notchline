import SwiftUI

struct SettingsView: View {
    static let windowSize = CGSize(width: 666, height: 625)

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaMonitor
    @ObservedObject var signals: SystemSignals
    let quit: () -> Void
    var isPreview = false

    @ViewState private var selection: SettingsSection = .general
    @ViewState private var playbackPreview: SettingsPlaybackPreview = .extended
    @ViewState private var previewBluetoothEnabled = false
    @ViewState private var previewPlaybackEnabled = true
    @ViewState private var previewKeyboardAllowed = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
            Rectangle().fill(SettingsPalette.border).frame(width: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    SettingsSectionIcon(section: selection)
                    Text(selection.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 17)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        panel
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .id(selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(isPreview || reduceTransparency ? SettingsPalette.window : .black.opacity(0.42))
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(SettingsPalette.text)
        .environment(\.colorScheme, .dark)
        .tint(SettingsPalette.accent)
    }

    @ViewBuilder private var panel: some View {
        switch selection {
        case .general:
            general
        case .battery:
            battery
        case .connectivity:
            connectivity
        case .focus:
            focus
        case .display:
            levelSettings(.display)
        case .sound:
            levelSettings(.sound)
        case .nowPlaying:
            NowPlayingSettings(
                playbackEnabled: isPreview ? $previewPlaybackEnabled : Binding(get: { media.enabled }, set: media.setEnabled),
                preview: $playbackPreview,
                outline: model.outline
            )
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                SettingsToggleRow(title: "Contrast outline", symbol: "circle.lefthalf.filled", isOn: $model.outline)
            }
            SettingsGroupHeading(title: "Preview")
                .padding(.top, 7)
            SettingsCard {
                SettingsPreviewStage {
                    let shape = NotchPresentation.idle.contour
                    shape.fill(.black)
                        .overlay {
                            if model.outline { shape.stroke(.white.opacity(0.5), lineWidth: 1).clipShape(shape) }
                        }
                        .frame(width: 182, height: 21)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .padding(10)
            }
            SettingsCard {
                SettingsRow {
                    Text("Notchline")
                    Spacer()
                    Button("Quit Notchline", action: quit)
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder private var battery: some View {
        SettingsCard {
            SettingsToggleRow(title: "Battery alerts", symbol: SettingsSection.battery.symbol, isOn: $model.powerAlerts)
            SettingsDivider()
            SettingsValueRow(
                title: "Battery charge",
                value: model.power.map { "\($0.percentage)%" } ?? "Unavailable",
                showsPill: model.power != nil
            )
        }
        SettingsGroupHeading(title: "Preview")
            .padding(.top, 7)
        SettingsAlertPreview(
            alert: .power(PowerState(percentage: 10, pluggedIn: false, lowPower: false), title: "Low battery"),
            caption: "Low battery alert"
        )
    }

    @ViewBuilder private var connectivity: some View {
        SettingsCard {
            SettingsToggleRow(title: "Headphone alerts", symbol: SettingsSection.connectivity.symbol, isOn: $model.headphonesAlerts)
            SettingsDivider()
            SettingsToggleRow(
                title: "Detect Bluetooth connections",
                isOn: isPreview ? $previewBluetoothEnabled : Binding(get: { signals.bluetoothEnabled }, set: signals.setBluetoothEnabled)
            )
        }
        SettingsGroupHeading(title: "Preview")
            .padding(.top, 7)
        SettingsAlertPreview(
            alert: .headphones("AirPods Pro", "airpodspro", connected: true, battery: 72),
            caption: "AirPods Pro connected"
        )
    }

    @ViewBuilder private var focus: some View {
        SettingsCard {
            SettingsToggleRow(title: "Focus alerts", symbol: SettingsSection.focus.symbol, isOn: $model.focusAlerts)
            SettingsDivider()
            SettingsValueRow(title: "Focus sharing", value: model.focusAccess.isEmpty ? "Access required" : model.focusAccess)
            if model.focusAccess != "Focus sharing enabled" {
                SettingsDivider()
                SettingsRow {
                    Button("Allow Focus Status…") {
                        if isPreview { model.focusAccess = "Focus sharing enabled" }
                        else { signals.requestFocusAccess() }
                    }
                }
            }
        }
        SettingsGroupHeading(title: "Preview")
            .padding(.top, 7)
        SettingsAlertPreview(alert: .focus(true), caption: "Focus on")
    }

    private func levelSettings(_ section: SettingsSection) -> some View {
        let isDisplay = section == .display
        return LevelSettings(
            section: section,
            alertsEnabled: isDisplay ? $model.brightnessAlerts : $model.volumeAlerts,
            level: isDisplay ? brightness : volume,
            output: model.output,
            usesNotchlineIndicators: isPreview ? previewKeyboardAllowed : signals.replacesSystemHUD,
            allowKeyboardControls: {
                if isPreview { previewKeyboardAllowed = true }
                else { signals.openAccessibilitySettings() }
            },
            controlError: isDisplay ? signals.brightnessControlError : signals.volumeControlError
        )
    }

    private var brightness: Binding<Double>? {
        guard let current = model.brightness else { return nil }
        return Binding(get: { model.brightness ?? current }, set: { level in
            if isPreview { model.brightness = level }
            else { signals.setBrightness(level) }
        })
    }

    private var volume: Binding<Double>? {
        guard let output = model.output, let current = output.volume else { return nil }
        return Binding(get: { model.output?.volume ?? current }, set: { level in
            if isPreview {
                model.output = SoundOutput(
                    id: output.id, source: output.source, name: output.name, transport: output.transport,
                    volume: level, muted: output.muted
                )
            } else {
                signals.setVolume(level)
            }
        })
    }
}

#if DEBUG
#Preview("Notchline Settings") {
    let model = NotchModel(defaults: UserDefaults(suiteName: "local.notchline.settings-preview")!)
    model.brightness = 0.64
    model.output = SoundOutput(id: 0, source: nil, name: "AirPods Pro", transport: nil, volume: 0.44, muted: false)
    model.power = PowerState(percentage: 72, pluggedIn: false, lowPower: false)
    return SettingsView(model: model, media: MediaMonitor(model: model), signals: SystemSignals(model: model), quit: {}, isPreview: true)
}
#endif
