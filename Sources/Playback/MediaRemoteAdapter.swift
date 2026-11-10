import Foundation

enum MediaRemoteAdapter {
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

    static func makeProcess(arguments: [String]) -> Process? {
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
