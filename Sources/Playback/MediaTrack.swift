import Foundation

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

    init?(payload: Payload, now: Date) {
        guard let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let artist = payload.artist ?? ""
        sourceBundleID = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier ?? ""
        id = [sourceBundleID, payload.uniqueIdentifier ?? title, artist]
            .joined(separator: "\u{1f}")
        self.title = title
        self.artist = artist
        playing = payload.playing ?? false
        duration = Self.validMicroseconds(payload.durationMicros) / 1_000_000
        isLive = payload.isLiveStream ?? (duration == 0 && Self.browsers.contains(sourceBundleID))
        canSkip = !isLive && payload.prohibitsSkip != true
        elapsed = Self.validMicroseconds(payload.elapsedTimeMicros) / 1_000_000
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

    private static func validMicroseconds(_ value: Double?) -> Double {
        guard let value, value.isFinite, (0...86_400_000_000_000).contains(value) else { return 0 }
        return value
    }

    struct Payload: Decodable {
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
