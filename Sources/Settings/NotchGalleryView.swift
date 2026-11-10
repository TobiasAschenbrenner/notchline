import SwiftUI

struct NotchGalleryView: View {
    enum Scene: String, CaseIterable, Identifiable {
        case playing = "Compact"
        case playback = "Playback"
        case deviceVolume = "Device volume"
        case airpods = "AirPods"
        case focus = "Focus"
        case volume = "Volume"
        case brightness = "Brightness"
        case battery = "Battery"
        var id: Self { self }
    }

    @StateObject private var demo = Demo()
    @ViewState private var scene: Scene = .playback

    var body: some View {
        VStack(spacing: 8) {
            NotchView(model: demo.model, media: demo.media, signals: demo.signals, geometry: .preview, sample: true)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack(alignment: .top) {
                        Color(red: 0.12, green: 0.10, blue: 0.23)
                        Rectangle().fill(.white.opacity(0.10)).frame(height: NotchGeometry.preview.cameraHeight)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            HStack(spacing: 5) {
                ForEach(Scene.allCases) { choice in
                    Button(choice.rawValue) {
                        scene = choice
                        demo.show(choice)
                    }
                    .buttonStyle(.bordered)
                    .tint(scene == choice ? .accentColor : .secondary)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { demo.show(scene) }
    }

    @MainActor
    private final class Demo: ObservableObject {
        let model = NotchModel()
        lazy var media = MediaMonitor(model: model)
        lazy var signals = SystemSignals(model: model)

        init() {
            model.output = SoundOutput(id: 0, source: nil, name: "AirPods Pro", transport: nil, volume: 0.38, muted: false)
            model.updateTrack(MediaTrack(sampleAt: .now))
        }

        func show(_ scene: Scene) {
            model.setExpanded(scene == .playback || scene == .deviceVolume)
            model.outputVolumeOpen = scene == .deviceVolume
            switch scene {
            case .playing, .playback, .deviceVolume: break
            case .airpods: model.show(.headphones("AirPods Pro", "airpodspro", connected: true, battery: 72), isPreview: true)
            case .focus: model.show(.focus(true), isPreview: true)
            case .volume: model.show(.volume(0.64, muted: false), isPreview: true)
            case .brightness: model.show(.brightness(0.47), isPreview: true)
            case .battery:
                model.show(.power(PowerState(percentage: 10, pluggedIn: false, lowPower: false), title: "Low battery"), isPreview: true)
            }
        }
    }
}
