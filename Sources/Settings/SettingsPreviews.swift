import SwiftUI

struct SettingsPreviewStage<Content: View>: View {
    var height: CGFloat = 65
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Color(red: 0.19, green: 0.18, blue: 0.27)
                    Rectangle().fill(.white.opacity(0.19)).frame(height: 21)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SettingsAlertPreview: View {
    let alert: NotchAlert
    let caption: String
    var output: SoundOutput? = nil

    var body: some View {
        let geometry = NotchGeometry(cameraWidth: 116, cameraHeight: 23)
        let frame = NotchFrame(.alert(alert.kind), geometry: geometry, alert: alert)
        SettingsCard {
            VStack(spacing: 7) {
                SettingsPreviewStage {
                    frame.contour.fill(.black)
                        .overlay {
                            NotchAlertView(alert: alert, frame: frame, cameraHeight: geometry.cameraHeight, output: output)
                                .foregroundStyle(.white)
                        }
                        .frame(width: frame.size.width, height: frame.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .padding(10)
        }
    }
}

enum SettingsPlaybackPreview: String, CaseIterable {
    case compact = "Compact"
    case extended = "Extended"

    var symbol: String { self == .compact ? "minus" : "play.fill" }
}

struct NowPlayingSettings: View {
    @Binding var playbackEnabled: Bool
    @Binding var preview: SettingsPlaybackPreview
    let outline: Bool
    @StateObject private var sample = Sample()

    var body: some View {
        let geometry = NotchGeometry.preview
        let previewScale: CGFloat = 0.72
        SettingsCard {
            SettingsToggleRow(title: "Show system playback", symbol: SettingsSection.nowPlaying.symbol, isOn: $playbackEnabled)
        }
        SettingsGroupHeading(title: "Preview")
            .padding(.top, 7)
        SettingsCard {
            SettingsPreviewStage(height: 160) {
                NotchView(model: sample.model, media: sample.media, signals: sample.signals, geometry: geometry, sample: true)
                    .scaleEffect(previewScale, anchor: .top)
                    // A scale effect changes the drawing, but SwiftUI still lays out the original width.
                    .frame(width: geometry.panelWidth * previewScale)
            }
            SettingsDivider()
            HStack(spacing: 12) {
                ForEach(SettingsPlaybackPreview.allCases, id: \.self) { choice in
                    previewChoice(choice)
                }
            }
            .padding(11)
        }
        .onChange(of: preview, initial: true) { sample.select(preview) }
        .onChange(of: outline, initial: true) { sample.model.outline = outline }
    }

    private func previewChoice(_ choice: SettingsPlaybackPreview) -> some View {
        let selected = preview == choice
        let shape = RoundedRectangle(cornerRadius: 9)
        return Button {
            preview = choice
        } label: {
            VStack(spacing: 6) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? SettingsPalette.accent : SettingsPalette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(selected ? SettingsPalette.accent.opacity(0.14) : .white.opacity(0.05), in: shape)
                    .overlay { shape.strokeBorder(SettingsPalette.border, lineWidth: 1) }
                    .overlay {
                        if selected {
                            shape.inset(by: -2).strokeBorder(SettingsPalette.accent, lineWidth: 2)
                        }
                    }
                    .accessibilityHidden(true)
                Text(choice.rawValue)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? SettingsPalette.text : SettingsPalette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @MainActor
    private final class Sample: ObservableObject {
        let model = NotchModel(defaults: UserDefaults(suiteName: "local.notchline.settings-preview")!)
        lazy var media = MediaMonitor(model: model)
        lazy var signals = SystemSignals(model: model)

        init() {
            model.updateTrack(MediaTrack(sampleAt: .now))
        }

        func select(_ preview: SettingsPlaybackPreview) {
            model.setExpanded(preview == .extended)
        }
    }
}
