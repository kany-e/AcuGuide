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
// (the same kind of one-line visual nudge TE3 needed). Markers are tappable (onSelect). Shared
// marker/material/mesh/tap helpers live in SceneKitAtlas.
struct HandModel3DView: UIViewRepresentable {
    var onSelect: (Acupoint) -> Void = { _ in }

    // Atlas→dorsal-plane mapping. After centre+scale+rotate, fingers run along world Y and the
    // dorsal face looks toward +Z (the camera). These map atlas (x,y in 360×440) → world (X,Y);
    // each marker is then raycast onto the surface. Tweak here if the layout needs nudging. Only
    // points whose atlas (x,y) falls inside [ax/ay range] are placed — so the dorsal hand points
    // (TE3/SI3/PC8/HT7) map on, while the forearm points (PC6 y=344 / SJ5 y=320) are left to the
    // body atlas rather than fired off the hand mesh.
    enum HandMarkerCalib {
        static let flipX = false
        static let flipY = true                 // atlas y grows down (toward wrist) → world Y grows up
        static let spanX: Float = 0.30          // world half-width the atlas x-range maps onto
        static let spanY: Float = 0.42          // world half-height the atlas y-range maps onto
        static let centerX: Float = 0
        static let centerY: Float = 0.0
        static let axMin: Double = 88,  axMax: Double = 248   // atlas x extent of the hand
        static let ayMin: Double = 45,  ayMax: Double = 300   // atlas y extent of the hand
        static func contains(_ ax: Double, _ ay: Double) -> Bool {
            ax >= axMin && ax <= axMax && ay >= ayMin && ay <= ayMax
        }
        static func world(_ ax: Float, _ ay: Float) -> (Float, Float) {
            var u = (ax - Float(axMin)) / Float(axMax - axMin) - 0.5
            var v = (ay - Float(ayMin)) / Float(ayMax - ayMin) - 0.5
            if flipX { u = -u }
            if flipY { v = -v }
            return (centerX + u * 2 * spanX, centerY + v * 2 * spanY)
        }
    }

    func makeCoordinator() -> AcuTapCoordinator { AcuTapCoordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        AtlasMarkers.addStudioLighting(to: scene)
        view.scene = scene
        context.coordinator.view = view

        if let url = Bundle.main.url(forResource: "hand_low_poly", withExtension: "glb") {
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                guard status == .complete, let asset = maybeAsset else { return }
                let gltf = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    guard let mesh = AtlasMarkers.unitMesh(from: gltf, material: AtlasMarkers.meshMaterial()) else { return }
                    mesh.eulerAngles = SCNVector3(0, 0.72, 0)   // square the posed mesh to a dorsal view
                    scene.rootNode.addChildNode(mesh)

                    placeMarkers(in: scene)                      // raycast atlas points onto the surface
                    AtlasMarkers.installCamera(z: 2.3, in: scene, for: view)
                }
            }
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(AcuTapCoordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // Raycast each in-range hand atlas point onto the dorsal surface and drop a tappable marker.
    private func placeMarkers(in scene: SCNScene) {
        for pt in Acupoint.all where pt.region == "hand" && HandMarkerCalib.contains(pt.x, pt.y) {
            let (X, Y) = HandMarkerCalib.world(Float(pt.x), Float(pt.y))
            // Dorsal points (requiresDorsal) raycast onto the back (camera-facing) surface; palmar
            // points (PC8/HT7) raycast onto the far PALM surface so they sit on the palm. Markers are
            // depth-tested against the opaque hand, so palmar ones hide until you rotate to the palm.
            let fromFront = pt.requiresDorsal
            let from = SCNVector3(X, Y, fromFront ? 1.5 : -1.5)
            let to   = SCNVector3(X, Y, fromFront ? -1.5 : 1.5)
            let hits = scene.rootNode.hitTestWithSegment(from: from, to: to, options: [
                SCNHitTestOption.backFaceCulling.rawValue: false,
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
            ])
            guard let h = hits.first else { continue }
            let p = h.worldCoordinates
            let dz: Float = fromFront ? 0.02 : -0.02       // sit just proud of the hit surface
            scene.rootNode.addChildNode(AtlasMarkers.node(
                id: pt.id, color: UIColor(MeridianColors.color(pt.meridian)),
                coreRadius: 0.022, haloRadius: 0.04, at: SCNVector3(p.x, p.y, p.z + dz), depthTested: true))
        }
    }
}
