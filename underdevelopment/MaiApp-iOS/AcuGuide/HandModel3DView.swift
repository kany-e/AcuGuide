import SwiftUI
import SceneKit
import GLTFKit2
import simd

// Detailed 3D hand (hand_low_poly.glb by scribbletoad, CC-BY 4.0) for the hand drill-down — it has
// real fingers, unlike the body's low-poly mitten. Static mesh (no rig): render the geometry
// directly, centered + scaled to a unit box, squared to a dorsal view, with pinch/drag to rotate.
//
// Acupoint markers: this asset is arbitrarily posed in its own coordinate frame, so axis-aligned
// bbox-fraction placement lands off-surface. Instead we map the VALIDATED 2D hand-atlas positions
// (the same 360×440 box HandAtlasView uses) into the dorsal viewing plane and RAYCAST each onto the
// mesh surface in world space — robust to the mesh's odd local axes. The mapping is a small tunable
// affine (HandMarkerCalib); if the points read mirrored/rotated on device, flip one flag there
// (the same kind of one-line visual nudge TE3 needed). Markers are tappable (onSelect).
struct HandModel3DView: UIViewRepresentable {
    var onSelect: (Acupoint) -> Void = { _ in }

    // Atlas→dorsal-plane mapping. After centre+scale+rotate, fingers run along world Y and the
    // dorsal face looks toward +Z (the camera). These map atlas (x,y in 360×440) → world (X,Y);
    // each marker is then raycast onto the surface. Tweak here if the layout needs nudging.
    private enum HandMarkerCalib {
        static let flipX = false
        static let flipY = true                 // atlas y grows down (toward wrist) → world Y grows up
        static let spanX: Float = 0.30          // world half-width the atlas x-range maps onto
        static let spanY: Float = 0.42          // world half-height the atlas y-range maps onto
        static let centerX: Float = 0
        static let centerY: Float = 0.0
        static let axMin: Float = 88,  axMax: Float = 248   // atlas x extent of the hand
        static let ayMin: Float = 45,  ayMax: Float = 300   // atlas y extent of the hand
        static func world(_ ax: Float, _ ay: Float) -> (Float, Float) {
            var u = (ax - axMin) / (axMax - axMin) - 0.5
            var v = (ay - ayMin) / (ayMax - ayMin) - 0.5
            if flipX { u = -u }
            if flipY { v = -v }
            return (centerX + u * 2 * spanX, centerY + v * 2 * spanY)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient
        amb.light?.intensity = 740; amb.light?.color = UIColor.white
        scene.rootNode.addChildNode(amb)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .directional
        fill.light?.intensity = 240; fill.light?.color = UIColor(Color(hex: "#fffaf0"))
        fill.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi / 7, 0)
        scene.rootNode.addChildNode(fill)
        view.scene = scene
        context.coordinator.view = view

        if let url = Bundle.main.url(forResource: "hand_low_poly", withExtension: "glb") {
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                guard status == .complete, let asset = maybeAsset else { return }
                let gltf = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    var found: SCNGeometry? = nil
                    gltf.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
                    guard let found else { return }
                    let geo = found.copy() as! SCNGeometry
                    geo.materials = [handMaterial()]
                    let mesh = SCNNode(geometry: geo)
                    let (lo, hi) = mesh.boundingBox
                    let cx = (lo.x + hi.x) / 2, cy = (lo.y + hi.y) / 2, cz = (lo.z + hi.z) / 2
                    mesh.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                    let extent = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
                    let s = extent > 0 ? 1.0 / extent : 1
                    mesh.scale = SCNVector3(s, s, s)
                    mesh.eulerAngles = SCNVector3(0, 0.72, 0)   // square the posed mesh to a dorsal view
                    scene.rootNode.addChildNode(mesh)

                    placeMarkers(in: scene)                      // raycast atlas points onto the surface

                    let cam = SCNNode()
                    cam.camera = SCNCamera()
                    cam.camera?.fieldOfView = 45
                    cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
                    cam.position = SCNVector3(0, 0, 2.3)
                    scene.rootNode.addChildNode(cam)
                    view.pointOfView = cam
                    view.defaultCameraController.target = SCNVector3Zero
                }
            }
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // Raycast each hand-region atlas point onto the visible (dorsal) surface and drop a glowing,
    // tappable marker there. Points whose ray misses the mesh (e.g. forearm points off this model)
    // are skipped silently.
    private func placeMarkers(in scene: SCNScene) {
        for pt in Acupoint.all where pt.region == "hand" && pt.x > 0 && pt.y > 0 {
            let (X, Y) = HandMarkerCalib.world(Float(pt.x), Float(pt.y))
            let from = SCNVector3(X, Y, 1.5), to = SCNVector3(X, Y, -1.5)
            let hits = scene.rootNode.hitTestWithSegment(from: from, to: to, options: [
                SCNHitTestOption.backFaceCulling.rawValue: false,
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
            ])
            guard let h = hits.first else { continue }
            let p = h.worldCoordinates
            scene.rootNode.addChildNode(marker(for: pt, at: SCNVector3(p.x, p.y, p.z + 0.02)))
        }
    }

    private func marker(for pt: Acupoint, at pos: SCNVector3) -> SCNNode {
        let col = UIColor(MeridianColors.color(pt.meridian))
        let core = SCNSphere(radius: 0.022); core.firstMaterial = glowMat(col, 1.0)
        let halo = SCNSphere(radius: 0.04);  halo.firstMaterial = glowMat(col, 0.25)
        let node = SCNNode(geometry: core)
        let h = SCNNode(geometry: halo); h.renderingOrder = 14; node.addChildNode(h)
        node.position = pos
        node.name = "acu:" + pt.id
        node.renderingOrder = 15
        return node
    }

    private func glowMat(_ color: UIColor, _ opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.transparency = opacity
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        return m
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        let onSelect: (Acupoint) -> Void
        init(onSelect: @escaping (Acupoint) -> Void) { self.onSelect = onSelect }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = view else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for h in hits {
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name, name.hasPrefix("acu:") {
                        let id = String(name.dropFirst(4))
                        if let pt = Acupoint.all.first(where: { $0.id == id }) { onSelect(pt); return }
                    }
                    n = node.parent
                }
            }
        }
    }
}

private func handMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.metalness.contents = 0.0
    m.roughness.contents = 1.0
    m.diffuse.contents = UIColor(Color(hex: "#bcae93"))   // warm parchment-sage
    m.emission.contents = UIColor(Color(hex: "#2c3626")); m.emission.intensity = 0.10
    m.isDoubleSided = true
    return m
}
