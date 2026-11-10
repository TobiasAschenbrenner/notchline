import Metal
import RealityKit
import SwiftUI

struct AirPodsProGlyph: View {
    private static let openingAngle: Float = .pi
    private static let openingHoldDuration: TimeInterval = 0.25
    private static let revolutionDuration: TimeInterval = 6
    private static let model: Entity? = {
        guard MTLCreateSystemDefaultDevice() != nil,
              let url = Bundle.main.url(forResource: "AirPodsPro", withExtension: "usdz") else { return nil }
        return try? Entity.load(contentsOf: url)
    }()

    let reduceMotion: Bool
    @ViewState private var startedAt: Date?

    var body: some View {
        if let model = Self.model {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt ?? context.date)
                let rotationTime = max(0, elapsed - Self.openingHoldDuration)
                let fraction = rotationTime.truncatingRemainder(dividingBy: Self.revolutionDuration) / Self.revolutionDuration
                let turn = Self.openingAngle + (reduceMotion ? 0 : Float(fraction) * 2 * .pi)
                AirPodsProScene(model: model, turn: turn)
            }
            .frame(width: 24, height: 22)
            .onAppear { startedAt = .now }
        } else {
            Image(systemName: "airpodspro")
        }
    }
}

private struct AirPodsProScene: NSViewRepresentable {
    let model: Entity
    let turn: Float

    func makeCoordinator() -> Entity {
        let pivot = Entity()
        pivot.addChild(model.clone(recursive: true))
        return pivot
    }

    func makeNSView(context: Context) -> ARView {
        let view = ARView(frame: CGRect(x: 0, y: 0, width: 24, height: 22))
        view.environment.background = .color(.clear)

        let anchor = AnchorEntity(world: SIMD3<Float>.zero)
        anchor.addChild(context.coordinator)

        let camera = PerspectiveCamera()
        // A level camera with a narrow field of view keeps the stems aligned as the pair turns.
        camera.camera.fieldOfViewInDegrees = 5.5
        camera.look(at: .zero, from: [0, 0, 1.4], relativeTo: nil)
        anchor.addChild(camera)

        anchor.addChild(light(from: [-2, 3, 4], intensity: 2_200))
        anchor.addChild(light(from: [3, 1, 2], intensity: 800))
        anchor.addChild(light(from: [0, 2, -3], intensity: 1_600))
        view.scene.addAnchor(anchor)
        return view
    }

    func updateNSView(_ view: ARView, context: Context) {
        context.coordinator.orientation = simd_quatf(angle: turn, axis: [0, 1, 0])
    }

    private func light(from position: SIMD3<Float>, intensity: Float) -> DirectionalLight {
        let light = DirectionalLight()
        light.light.intensity = intensity
        light.look(at: .zero, from: position, relativeTo: nil)
        return light
    }
}
