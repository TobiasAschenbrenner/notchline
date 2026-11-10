import Foundation

enum PlaybackCommand {
    case previous, toggle, next, seek(Double)
}

enum MediaRemoteAdapter {
    struct Snapshot {
        let track: MediaTrack?
    }

    struct StreamDecoder {
        private let maximumLineBytes: Int
        private var pending = Data()
        private var discardingOversizedLine = false

        init(maximumLineBytes: Int = 8_000_000) {
            self.maximumLineBytes = maximumLineBytes
        }

        mutating func consume(_ bytes: Data, now: Date) -> [Snapshot] {
            var snapshots: [Snapshot] = []
            var remaining = bytes
            while let newline = remaining.firstIndex(of: 0x0A) {
                append(remaining[..<newline])
                if !discardingOversizedLine, let snapshot = MediaRemoteAdapter.decode(pending, now: now) {
                    snapshots.append(snapshot)
                }
                pending.removeAll()
                discardingOversizedLine = false
                remaining = remaining[remaining.index(after: newline)...]
            }
            append(remaining)
            return snapshots
        }

        private mutating func append(_ bytes: Data) {
            guard !discardingOversizedLine else { return }
            guard bytes.count <= maximumLineBytes - pending.count else {
                pending.removeAll()
                // A later pipe read can still belong to this line.
                discardingOversizedLine = true
                return
            }
            pending.append(bytes)
        }
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

    static func makeStreamProcess() -> Process? {
        makeProcess(arguments: ["stream", "--no-diff", "--micros", "--debounce=65"])
    }

    static func makeControlProcess(for command: PlaybackCommand, track: MediaTrack) -> Process? {
        let arguments: [String]
        switch command {
        case .previous:
            guard track.canSkip else { return nil }
            arguments = ["send", "5"]
        case .toggle:
            arguments = ["send", "2"]
        case .next:
            guard track.canSkip else { return nil }
            arguments = ["send", "4"]
        case .seek(let position):
            guard track.canSeek, position.isFinite else { return nil }
            let micros = Int64(min(track.duration, max(0, position)) * 1_000_000)
            arguments = ["seek", String(micros)]
        }
        return makeProcess(arguments: arguments)
    }

    private static func makeProcess(arguments: [String]) -> Process? {
        guard let resource = Bundle.main.resourceURL,
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let script = resource.appendingPathComponent("mediaremote-adapter.pl")
        let adapter = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: adapter.appendingPathComponent("MediaRemoteAdapter").path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, adapter.path] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }
}
