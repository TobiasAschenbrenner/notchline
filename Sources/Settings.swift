import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaMonitor
    @ObservedObject var signals: SystemSignals
    let showOnDesktop: () -> Void
    let quit: () -> Void

    var body: some View {
        TabView {
            gallery.tabItem { Label("Notch", systemImage: "capsule") }
            playback.tabItem { Label("Playback", systemImage: "play.rectangle") }
            preferences.tabItem { Label("System", systemImage: "slider.horizontal.3") }
        }
        .padding(12)
        .frame(width: 565, height: 462)
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 45, height: 45)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notchline").font(.system(size: 20, weight: .semibold))
                    Text("Now Playing and system activity at the top of your Mac.").font(.callout).foregroundStyle(.secondary)
                }
            }
            GalleryView()
            HStack {
                Button("Show on Desktop", action: showOnDesktop)
                Spacer()
                Text("Hover over the notch to open it.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(13)
    }

    private var playback: some View {
        Form {
            Section("macOS Now Playing") {
                Toggle("Show system playback", isOn: Binding(get: { media.enabled }, set: media.setEnabled))
                Text(media.status).font(.callout).foregroundStyle(.secondary)
                Text("The notch follows the active session from macOS Now Playing, including browser media when it is available.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var preferences: some View {
        Form {
            Section("Appearance and motion") {
                Toggle("Contrast outline", isOn: $model.outline)
            }
            Section("System activity") {
                Toggle("Volume and brightness alerts", isOn: $model.levelAlerts)
                if model.levelAlerts {
                    LabeledContent("Keyboard indicators", value: signals.replacesSystemHUD ? "Notchline" : "macOS")
                    if !signals.replacesSystemHUD {
                        Text("Allow Notchline in Accessibility to replace the macOS volume and brightness indicators for the hardware keys.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Accessibility Settings…", action: signals.openAccessibilitySettings)
                    }
                }
                Toggle("Headphone alerts", isOn: $model.headphonesAlerts)
                Toggle("Detect Bluetooth connections", isOn: Binding(get: { signals.bluetoothEnabled }, set: signals.setBluetoothEnabled))
                Toggle("Focus alerts", isOn: $model.focusAlerts)
                Toggle("Battery alerts", isOn: $model.powerAlerts)
                HStack {
                    Button("Allow Focus Status…", action: signals.requestFocusAccess)
                    if !model.focusAccess.isEmpty {
                        Text(model.focusAccess).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Available signals") {
                LabeledContent("Audio output", value: model.output?.routeName ?? "Unavailable")
                LabeledContent("Display brightness", value: model.brightness?.formatted(.percent.precision(.fractionLength(0))) ?? "Unavailable")
                LabeledContent("Battery charge", value: model.power.map { "\($0.percentage)%" } ?? "Unavailable")
                if let output = model.output, let volume = output.volume {
                    Slider(value: Binding(get: { model.output?.volume ?? volume }, set: signals.setVolume)) {
                        Text("Output volume")
                    }
                }
                if let brightness = model.brightness {
                    Slider(value: Binding(get: { model.brightness ?? brightness }, set: signals.setBrightness)) {
                        Text("Brightness")
                    }
                }
                if let error = signals.controlError { Text(error).foregroundStyle(.secondary) }
            }
            Section {
                Button("Quit Notchline", action: quit)
            }
        }
        .formStyle(.grouped)
    }

}

private struct GalleryView: View {
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
