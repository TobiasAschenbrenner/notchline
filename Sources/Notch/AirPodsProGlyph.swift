import Metal
import RealityKit
import SwiftUI

struct AirPodsProGlyph: View {
    private static let canRenderModel = MTLCreateSystemDefaultDevice() != nil
    private static let revolutionDuration: TimeInterval = 6
    private static let entryAngle: Float = -.pi / 8

    let reduceMotion: Bool
    @ViewState private var startedAt = Date.now

    var body: some View {
        if Self.canRenderModel {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                let fraction = elapsed.truncatingRemainder(dividingBy: Self.revolutionDuration) / Self.revolutionDuration
                let turn = Self.entryAngle + Float(fraction) * 2 * .pi
                AirPodsProScene(turn: reduceMotion ? 0 : turn)
            }
            .frame(width: 24, height: 22)
        } else {
            Image(systemName: "airpodspro")
        }
    }
}

private struct AirPodsProScene: NSViewRepresentable {
    let turn: Float

    func makeCoordinator() -> Entity { AirPodsProModel.makePair() }

    func makeNSView(context: Context) -> ARView {
        let view = ARView(frame: CGRect(x: 0, y: 0, width: 24, height: 22))
        view.environment.background = .color(.clear)

        let anchor = AnchorEntity(world: SIMD3<Float>.zero)
        anchor.addChild(context.coordinator)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 29
        camera.look(at: .zero, from: [0, 0.12, 2.65], relativeTo: nil)
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

@MainActor
private enum AirPodsProModel {
    static func makePair() -> Entity {
        let pivot = Entity()
        pivot.addChild(earbud(inward: 1))
        pivot.addChild(earbud(inward: -1))
        return pivot
    }

    private static func earbud(inward: Float) -> Entity {
        let bud = Entity()
        bud.position.x = -inward * 0.37
        bud.orientation = simd_quatf(angle: -inward * 0.28, axis: [0, 1, 0])

        let plastic = SimpleMaterial(color: NSColor(white: 0.94, alpha: 1), roughness: 0.34, isMetallic: false)
        let silicone = SimpleMaterial(color: NSColor(white: 0.78, alpha: 1), roughness: 0.72, isMetallic: false)
        let grille = SimpleMaterial(color: NSColor(white: 0.055, alpha: 1), roughness: 0.6, isMetallic: false)
        let contact = SimpleMaterial(color: NSColor(white: 0.48, alpha: 1), roughness: 0.36, isMetallic: true)
        let sphere = MeshResource.generateSphere(radius: 1)

        func ellipsoid(_ radii: SIMD3<Float>, at position: SIMD3<Float>, material: SimpleMaterial) -> ModelEntity {
            let part = ModelEntity(mesh: sphere, materials: [material])
            part.scale = radii
            part.position = position
            bud.addChild(part)
            return part
        }

        let housing = ellipsoid([0.235, 0.206, 0.185], at: [-inward * 0.025, 0.19, 0], material: plastic)
        housing.orientation = simd_quatf(angle: -inward * 0.28, axis: [0, 0, 1])
        _ = ellipsoid([0.094, 0.157, 0.092], at: [-inward * 0.108, 0.04, 0.013], material: plastic)

        let stem = ModelEntity(mesh: .generateBox(size: [0.145, 0.51, 0.135], cornerRadius: 0.054), materials: [plastic])
        stem.position = [-inward * 0.116, -0.181, 0.01]
        stem.orientation = simd_quatf(angle: -inward * 0.035, axis: [0, 0, 1])
        bud.addChild(stem)

        let tip = ellipsoid([0.143, 0.117, 0.109], at: [inward * 0.154, 0.173, 0.105], material: silicone)
        tip.orientation = simd_quatf(angle: -inward * 0.65, axis: [0, 1, 0])

        let nozzle = ellipsoid([0.056, 0.065, 0.018], at: [inward * 0.237, 0.174, 0.184], material: grille)
        nozzle.orientation = tip.orientation

        let frontVent = ellipsoid([0.076, 0.043, 0.016], at: [-inward * 0.058, 0.254, 0.175], material: grille)
        frontVent.orientation = simd_quatf(angle: inward * 0.38, axis: [0, 0, 1])

        let rearVent = ellipsoid([0.043, 0.105, 0.018], at: [-inward * 0.082, 0.18, -0.174], material: grille)
        rearVent.orientation = simd_quatf(angle: -inward * 0.12, axis: [0, 0, 1])

        _ = ellipsoid([0.052, 0.02, 0.046], at: [-inward * 0.124, -0.427, 0.01], material: contact)
        return bud
    }
}
