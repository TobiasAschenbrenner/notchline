import SwiftUI

struct NotchPlaybackView: View {
    let track: MediaTrack?
    let status: String
    let output: SoundOutput?
    let outputVolume: Binding<Double>?
    let cameraHeight: CGFloat
    let volumeRowProgress: Double
    @Binding var isVolumeControlOpen: Bool
    let sendCommand: (MediaMonitor.Command) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let track {
                header {
                    VStack(alignment: .leading, spacing: 1) {
                        PlaybackTitle(title: track.title)
                        if !track.artist.isEmpty {
                            Text(track.artist).font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }
                }
                PlaybackScrubber(track: track) { sendCommand(.seek($0)) }
                    .padding(.horizontal, track.isLive ? 36 : 28)
            } else {
                header {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nothing playing").font(.system(size: 13, weight: .medium))
                        Text(status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
                Color.clear.frame(height: 16)
            }
            transport(track)
            if volumeRowProgress > 0 {
                volumeControl
                    .padding(.horizontal, 48)
                    .frame(height: 16)
                    .modifier(NotchDetail(progress: volumeRowProgress, blur: 3, y: -6))
                    .allowsHitTesting(volumeRowProgress > 0.8)
            }
        }
        .padding(.top, PlaybackHeaderLayout.topInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func header<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: PlaybackHeaderLayout.artworkWidth)
            content()
                .padding(.leading, track?.playing == false ? 4 : 0)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: max(0, cameraHeight - 27.5))
            Color.clear.frame(width: PlaybackWaveform.width)
        }
        .frame(height: PlaybackHeaderLayout.artworkWidth)
        .padding(.leading, PlaybackHeaderLayout.artworkInset)
        .padding(.trailing, PlaybackHeaderLayout.waveformInset)
    }

    private func transport(_ track: MediaTrack?) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: IconControl.width, height: 1)
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                IconControl(icon: "backward.fill", label: "Previous", size: 18) {
                    sendCommand(.previous)
                }
                .disabled(track?.canSkip == false)
                .foregroundStyle(.white.opacity(track?.canSkip == false ? 1 : 0.52))
                IconControl(icon: track?.playing == true ? "pause.fill" : "play.fill",
                            label: track?.playing == true ? "Pause" : "Play", size: 27) {
                    sendCommand(.toggle)
                }
                IconControl(icon: "forward.fill", label: "Next", size: 18) {
                    sendCommand(.next)
                }
                .disabled(track?.canSkip == false)
                .foregroundStyle(.white.opacity(track?.canSkip == false ? 1 : 0.52))
            }
            .disabled(track == nil)
            .opacity(track == nil ? 0.36 : 1)
            Spacer(minLength: 0)
            IconControl(icon: output?.playerIcon ?? "laptopcomputer",
                        label: "Volume for \(output?.routeName ?? "current output")",
                        size: 18, highlighted: isVolumeControlOpen) {
                isVolumeControlOpen.toggle()
            }
            .foregroundStyle(.white.opacity(isVolumeControlOpen ? 0.72 : 0.55))
            .accessibilityValue(isVolumeControlOpen ? Text("Expanded") : Text("Collapsed"))
        }
        .padding(.horizontal, 32)
        .frame(height: 42)
    }

    @ViewBuilder private var volumeControl: some View {
        if let output, let outputVolume {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").frame(width: 12)
                OutputVolumeRail(
                    level: outputVolume,
                    label: "Volume for \(output.routeName)"
                )
                Image(systemName: "speaker.wave.2.fill").frame(width: 12)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.48))
        } else {
            Text("Volume unavailable for this output")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct OutputVolumeRail: View {
    @Binding var level: Double
    let label: String

    var body: some View {
        GeometryReader { proxy in
            LevelMeter(value: level, height: 6, trackOpacity: 0.16, fillOpacity: 0.41, roundsFill: false)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { change in
                        level = min(1, max(0, change.location.x / max(1, proxy.size.width)))
                    })
        }
        .accessibilityRepresentation {
            Slider(value: $level, in: 0...1) { Text(label) }
        }
    }
}

private struct IconControl: View {
    static let width: CGFloat = 48
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var isHovered = false

    let icon: String
    let label: String
    let size: CGFloat
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: Self.width, height: 46)
                .background(.white.opacity(highlighted || (isEnabled && isHovered) ? 0.10 : 0),
                            in: RoundedRectangle(cornerRadius: 15))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}
