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
        VStack(spacing: 11) {
            if let track {
                HStack(spacing: 13) {
                    Color.clear.frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if !track.artist.isEmpty {
                            Text(track.artist).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }
                    .offset(y: max(0, cameraHeight - 25))
                    Spacer(minLength: 5)
                    Color.clear.frame(width: PlaybackWaveform.width, height: 14)
                }
                PlaybackScrubber(track: track) { sendCommand(.seek($0)) }
                transport(track)
            } else {
                HStack(spacing: 13) {
                    Color.clear.frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing playing").font(.system(size: 15, weight: .semibold))
                        Text(status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                Color.clear.frame(height: 18)
                transport(nil)
            }
            if volumeRowProgress > 0 {
                volumeControl
                    .padding(.horizontal, 9)
                    .padding(.top, 6)
                    .modifier(NotchDetail(progress: volumeRowProgress, blur: 3, y: -6))
                    .allowsHitTesting(volumeRowProgress > 0.8)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 17)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func transport(_ track: MediaTrack?) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 31, height: 1)
            Spacer(minLength: 0)
            HStack(spacing: 23) {
                IconControl(icon: "backward.fill", label: "Previous", size: 20) {
                    sendCommand(.previous)
                }
                .disabled(track?.canSkip == false)
                .opacity(track?.canSkip == false ? 0.36 : 1)
                IconControl(icon: track?.playing == true ? "pause.fill" : "play.fill",
                            label: track?.playing == true ? "Pause" : "Play", size: 23) {
                    sendCommand(.toggle)
                }
                IconControl(icon: "forward.fill", label: "Next", size: 20) {
                    sendCommand(.next)
                }
                .disabled(track?.canSkip == false)
                .opacity(track?.canSkip == false ? 0.36 : 1)
            }
            .disabled(track == nil)
            .opacity(track == nil ? 0.36 : 1)
            Spacer(minLength: 0)
            IconControl(icon: output?.playerIcon ?? "laptopcomputer",
                        label: "Volume for \(output?.routeName ?? "current output")", size: 18) {
                isVolumeControlOpen.toggle()
            }
            .foregroundStyle(.white.opacity(isVolumeControlOpen ? 1 : 0.55))
        }
        .frame(height: 36)
    }

    @ViewBuilder private var volumeControl: some View {
        if let output, let outputVolume {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").frame(width: 15)
                OutputVolumeRail(
                    level: outputVolume,
                    label: "Volume for \(output.routeName)"
                )
                Image(systemName: "speaker.wave.3.fill").frame(width: 15)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
            .frame(height: 25)
        } else {
            Text("Volume unavailable for this output")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: 25)
        }
    }
}

private struct OutputVolumeRail: View {
    @Binding var level: Double
    let label: String

    var body: some View {
        GeometryReader { proxy in
            LevelMeter(value: level, height: 4, trackOpacity: 0.20, fillOpacity: 0.57)
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
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 31, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
