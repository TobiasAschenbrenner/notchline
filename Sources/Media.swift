import AppKit
import ImageIO
import SwiftUI

struct MediaTrack: Equatable {
    let id: String
    let title: String
    let artist: String
    let sourceBundleID: String
    let playing: Bool
    let elapsed: Double
    let duration: Double
    let rate: Double
    let sampledAt: Date
    let artwork: Data?
    let isLive: Bool
    let canSkip: Bool

    var canSeek: Bool { !isLive && duration > 0 }
    var fallbackArtwork: String { Self.browsers.contains(sourceBundleID) ? "play.rectangle.fill" : "music.note" }

    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
        "org.mozilla.firefox", "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    func position(at date: Date) -> Double {
        let position = max(0, elapsed + (playing ? max(0, date.timeIntervalSince(sampledAt)) * rate : 0))
        return canSeek ? min(duration, position) : position
    }

    fileprivate init?(payload: Payload, now: Date) {
        guard let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let artist = payload.artist ?? ""
        sourceBundleID = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier ?? ""
        id = [sourceBundleID, payload.uniqueIdentifier ?? title, artist]
            .joined(separator: "\u{1f}")
        self.title = title
        self.artist = artist
        playing = payload.playing ?? false
        duration = Self.validTime(payload.durationMicros) / 1_000_000
        isLive = payload.isLiveStream ?? (duration == 0 && Self.browsers.contains(sourceBundleID))
        canSkip = !isLive && payload.prohibitsSkip != true
        elapsed = Self.validTime(payload.elapsedTimeMicros) / 1_000_000
        rate = min(8, max(0, payload.playbackRate ?? 1))
        if let timestamp = payload.timestampEpochMicros, timestamp.isFinite, timestamp > 0 {
            sampledAt = min(now, Date(timeIntervalSince1970: timestamp / 1_000_000))
        } else {
            sampledAt = now
        }
        if let encoded = payload.artworkData, encoded.utf8.count <= 7_000_000 {
            artwork = Data(base64Encoded: encoded)
        } else {
            artwork = nil
        }
    }

    init(sampleAt now: Date) {
        id = "sample"
        title = "Night Crossing"
        artist = "Northline"
        sourceBundleID = "com.spotify.client"
        playing = true
        elapsed = 137
        duration = 226
        rate = 1
        sampledAt = now
        artwork = nil
        isLive = false
        canSkip = true
    }

    private static func validTime(_ value: Double?) -> Double {
        guard let value, value.isFinite, (0...86_400_000_000_000).contains(value) else { return 0 }
        return value
    }

    fileprivate struct Payload: Decodable {
        var title: String?
        var artist: String?
        var bundleIdentifier: String?
        var parentApplicationBundleIdentifier: String?
        var uniqueIdentifier: String?
        var playing: Bool?
        var durationMicros: Double?
        var elapsedTimeMicros: Double?
        var timestampEpochMicros: Double?
        var playbackRate: Double?
        var artworkData: String?
        var isLiveStream: Bool?
        var prohibitsSkip: Bool?
    }
}

@MainActor
final class MediaMonitor: ObservableObject {
    enum Command {
        case previous, toggle, next, seek(Double)
    }

    @Published private(set) var enabled = UserDefaults.standard.object(forKey: "systemMediaEnabled") as? Bool ?? true
    @Published private(set) var status = "Waiting for macOS Now Playing"
    @Published private(set) var image: NSImage?
    @Published private(set) var tint = Color(red: 0.72, green: 0.68, blue: 0.91)

    private let model: NotchModel
    private var stream: Process?
    private var pipe: Pipe?
    private var pending = Data()
    private var retries = 0
    private var retry: Task<Void, Never>?
    private var artwork: Data?
    private var commandProcess: Process?

    init(model: NotchModel) { self.model = model }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "systemMediaEnabled")
        if value { retries = 0; start() }
        else { stop(); status = "Now Playing is off" }
    }

    func start() {
        guard enabled, stream == nil else { return }
        guard let process = Self.makeProcess(["stream", "--no-diff", "--micros", "--debounce=65"]) else {
            status = "The macOS Now Playing adapter is missing"
            return
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { self?.streamEnded(process) }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let process, self?.stream === process else { return }
                self?.receive(data)
            }
        }
        self.pipe = pipe
        stream = process
        status = "Waiting for macOS Now Playing"
        do { try process.run() }
        catch { streamEnded(process) }
    }

    func stop() {
        retry?.cancel()
        retry = nil
        if let commandProcess, commandProcess.isRunning { commandProcess.terminate() }
        commandProcess = nil
        let process = stream
        clearStream()
        if let process, process.isRunning { process.terminate() }
        update(nil)
    }

    func control(_ command: Command) {
        guard enabled, let track = model.music, commandProcess == nil else { return }
        let arguments: [String]
        switch command {
        case .previous:
            guard track.canSkip else { return }
            arguments = ["send", "5"]
        case .toggle: arguments = ["send", "2"]
        case .next:
            guard track.canSkip else { return }
            arguments = ["send", "4"]
        case .seek(let position):
            guard track.canSeek, position.isFinite else { return }
            let micros = Int64(min(track.duration, max(0, position)) * 1_000_000)
            arguments = ["seek", String(micros)]
        }
        guard let process = Self.makeProcess(arguments) else { return }
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard self?.commandProcess === process else { return }
                self?.commandProcess = nil
            }
        }
        commandProcess = process
        do { try process.run() }
        catch { commandProcess = nil }
    }

    private func clearStream() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        stream = nil
        pending.removeAll(keepingCapacity: false)
    }

    private func streamEnded(_ process: Process) {
        guard stream === process else { return }
        clearStream()
        update(nil)
        status = "macOS Now Playing is unavailable"
        guard enabled, retries < 3 else { return }
        retries += 1
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    private func receive(_ data: Data) {
        pending.append(data)
        while let boundary = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: boundary)
            if line.count <= 8_000_000, let result = Self.decode(Data(line), now: .now) {
                retries = 0
                update(result.track)
                status = result.track == nil ? "Waiting for macOS Now Playing" : "Connected to macOS Now Playing"
            }
            pending.removeSubrange(...boundary)
        }
        if pending.count > 8_000_000 { pending.removeAll() }
    }

    private func update(_ track: MediaTrack?) {
        if artwork != track?.artwork {
            artwork = track?.artwork
            image = artwork.flatMap(Self.thumbnail)
            tint = image.flatMap(Self.artworkTint) ?? Color(red: 0.72, green: 0.68, blue: 0.91)
        }
        model.updateTrack(track)
    }

    struct Snapshot {
        let track: MediaTrack?
    }

    static func decode(_ data: Data, now: Date) -> Snapshot? {
        struct Event: Decodable {
            let type: String
            let diff: Bool
            let payload: MediaTrack.Payload
        }
        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.type == "data", !event.diff else { return nil }
        return Snapshot(track: MediaTrack(payload: event.payload, now: now))
    }

    private static func makeProcess(_ command: [String]) -> Process? {
        guard let resource = Bundle.main.resourceURL,
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let script = resource.appendingPathComponent("mediaremote-adapter.pl")
        let adapter = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: adapter.appendingPathComponent("MediaRemoteAdapter").path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, adapter.path] + command
        process.standardError = FileHandle.nullDevice
        return process
    }

    private static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func artworkTint(_ image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        pixel.interpolationQuality = .medium
        pixel.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = pixel.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return Color(red: 0.48 + Double(bytes[0]) / 490,
                     green: 0.48 + Double(bytes[1]) / 490,
                     blue: 0.48 + Double(bytes[2]) / 490)
    }
}
