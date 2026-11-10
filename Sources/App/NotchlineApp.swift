import AppKit

@main
struct NotchlineApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") {
            exit(NotchlineSelfTests.run() ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
