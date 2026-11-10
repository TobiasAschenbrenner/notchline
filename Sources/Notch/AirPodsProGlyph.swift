import Metal
import RealityKit
import SwiftUI

struct AirPodsProGlyph: View {
    private static let canRenderModel = MTLCreateSystemDefaultDevice() != nil
    private static let turnDuration: TimeInterval = 2.8

    let reduceMotion: Bool
    @ViewState private var startedAt = Date.now
    @ViewState private var isTurning = false

    var body: some View {
        if Self.canRenderModel {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isTurning)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                let progress = Float(min(1, max(0, elapsed / Self.turnDuration)))
                let turn = progress * progress * (3 - 2 * progress) * 2 * .pi
                AirPodsProScene(turn: reduceMotion || !isTurning ? 0 : turn)
            }
            .frame(width: 24, height: 22)
            .task(id: reduceMotion) {
                guard !reduceMotion else { isTurning = false; return }
                startedAt = .now
                isTurning = true
                try? await Task.sleep(for: .seconds(Self.turnDuration))
                if !Task.isCancelled { isTurning = false }
            }
        } else {
            Image(systemName: "airpodspro")
        }
    }
}

private struct AirPodsProScene: NSViewRepresentable {
    let turn: Float

    func makeCoordinator() -> AirPodsProPair { AirPodsProPair() }

    func makeNSView(context: Context) -> ARView {
        let view = ARView(frame: CGRect(x: 0, y: 0, width: 24, height: 22))
        view.environment.background = .color(.clear)

        let anchor = AnchorEntity(world: SIMD3<Float>.zero)
        anchor.addChild(context.coordinator.left)
        anchor.addChild(context.coordinator.right)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 29
        camera.look(at: .zero, from: [0, 0.12, 2.65], relativeTo: nil)
        anchor.addChild(camera)

        anchor.addChild(light(from: [-2, 3, 4], intensity: 2_400))
        anchor.addChild(light(from: [3, 1, 2], intensity: 900))
        anchor.addChild(light(from: [0, 2, -3], intensity: 1_800))
        view.scene.addAnchor(anchor)
        return view
    }

    func updateNSView(_ view: ARView, context: Context) {
        context.coordinator.rotate(turn)
    }

    private func light(from position: SIMD3<Float>, intensity: Float) -> DirectionalLight {
        let light = DirectionalLight()
        light.light.intensity = intensity
        light.look(at: .zero, from: position, relativeTo: nil)
        return light
    }
}

@MainActor
private final class AirPodsProPair {
    let left = AirPodsProPair.earbud(inward: 1)
    let right = AirPodsProPair.earbud(inward: -1)

    func rotate(_ turn: Float) {
        left.orientation = simd_quatf(angle: turn - 0.28, axis: [0, 1, 0])
        right.orientation = simd_quatf(angle: 0.28 - turn, axis: [0, 1, 0])
    }

    private static func earbud(inward: Float) -> Entity {
        let bud = Entity()
        bud.position.x = -inward * 0.38

        let plastic = SimpleMaterial(color: .white, roughness: 0.24, isMetallic: false)
        let silicone = SimpleMaterial(color: NSColor(white: 0.78, alpha: 1), roughness: 0.72, isMetallic: false)
        let grille = SimpleMaterial(color: NSColor(white: 0.07, alpha: 1), roughness: 0.6, isMetallic: false)
        let contact = SimpleMaterial(color: NSColor(white: 0.48, alpha: 1), roughness: 0.36, isMetallic: true)
        let sphere = MeshResource.generateSphere(radius: 1)

        func ellipsoid(_ radii: SIMD3<Float>, at position: SIMD3<Float>, material: SimpleMaterial) -> ModelEntity {
            let part = ModelEntity(mesh: sphere, materials: [material])
            part.scale = radii
            part.position = position
            bud.addChild(part)
            return part
        }

        let housing = ellipsoid([0.23, 0.24, 0.20], at: [0, 0.19, 0], material: plastic)
        housing.orientation = simd_quatf(angle: inward * 0.28, axis: [0, 0, 1])

        let stem = ModelEntity(mesh: .generateBox(size: [0.17, 0.54, 0.16], cornerRadius: 0.072), materials: [plastic])
        stem.position = [-inward * 0.08, -0.18, 0.01]
        stem.orientation = simd_quatf(angle: -inward * 0.16, axis: [0, 0, 1])
        bud.addChild(stem)

        let tip = ellipsoid([0.16, 0.135, 0.12], at: [inward * 0.16, 0.23, 0.105], material: silicone)
        tip.orientation = simd_quatf(angle: -inward * 0.65, axis: [0, 1, 0])

        let nozzle = ellipsoid([0.065, 0.072, 0.02], at: [inward * 0.249, 0.24, 0.194], material: grille)
        nozzle.orientation = tip.orientation

        let vent = ellipsoid([0.092, 0.045, 0.016], at: [-inward * 0.047, 0.27, 0.18], material: grille)
        vent.orientation = simd_quatf(angle: inward * 0.38, axis: [0, 0, 1])

        _ = ellipsoid([0.055, 0.021, 0.05], at: [-inward * 0.116, -0.435, 0.01], material: contact)
        return bud
    }
}
