import AppKit
import ImageIO
import SwiftUI

@MainActor
final class MediaMonitor: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.object(forKey: "systemMediaEnabled") as? Bool ?? true
    @Published private(set) var status = "Waiting for macOS Now Playing"
    @Published private(set) var image: NSImage?
    @Published private(set) var tint = Color(red: 0.72, green: 0.68, blue: 0.91)

    private let model: NotchModel
    private var streamProcess: Process?
    private var streamPipe: Pipe?
    private var streamDecoder = MediaRemoteAdapter.StreamDecoder()
    private var retryCount = 0
    private var retryTask: Task<Void, Never>?
    private var artworkData: Data?
    private var commandProcess: Process?

    init(model: NotchModel) { self.model = model }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "systemMediaEnabled")
        if value { retryCount = 0; start() }
        else { stop(); status = "Now Playing is off" }
    }

    func start() {
        guard enabled, streamProcess == nil else { return }
        guard let process = MediaRemoteAdapter.makeStreamProcess() else {
            status = "The macOS Now Playing adapter is missing"
            return
        }
        let streamPipe = Pipe()
        process.standardOutput = streamPipe
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { self?.streamEnded(process) }
        }
        streamPipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let process, self?.streamProcess === process else { return }
                self?.receive(data)
            }
        }
        self.streamPipe = streamPipe
        streamProcess = process
        status = "Waiting for macOS Now Playing"
        do { try process.run() }
        catch { streamEnded(process) }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        if let commandProcess, commandProcess.isRunning { commandProcess.terminate() }
        commandProcess = nil
        let process = streamProcess
        clearStream()
        if let process, process.isRunning { process.terminate() }
        update(nil)
    }

    func control(_ command: PlaybackCommand) {
        guard enabled, let track = model.track, commandProcess == nil,
              let process = MediaRemoteAdapter.makeControlProcess(for: command, track: track) else { return }
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
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        streamPipe = nil
        streamProcess = nil
        streamDecoder = .init()
    }

    private func streamEnded(_ process: Process) {
        guard streamProcess === process else { return }
        clearStream()
        update(nil)
        status = "macOS Now Playing is unavailable"
        guard enabled, retryCount < 3 else { return }
        retryCount += 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    private func receive(_ data: Data) {
        for snapshot in streamDecoder.consume(data, now: .now) {
            retryCount = 0
            update(snapshot.track)
            status = snapshot.track == nil ? "Waiting for macOS Now Playing" : "Connected to macOS Now Playing"
        }
    }

    private func update(_ track: MediaTrack?) {
        if artworkData != track?.artwork {
            artworkData = track?.artwork
            image = artworkData.flatMap(Self.thumbnail)
            tint = image.flatMap(Self.artworkTint) ?? Color(red: 0.72, green: 0.68, blue: 0.91)
        }
        model.updateTrack(track)
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
