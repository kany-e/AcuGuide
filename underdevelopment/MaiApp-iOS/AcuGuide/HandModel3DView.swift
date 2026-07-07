import SwiftUI
import SceneKit
import simd

// Detailed 3D hand (hand_low_poly.glb by scribbletoad, CC-BY 4.0) for the hand drill-down — it has
// real fingers, unlike the body's low-poly mitten. Static mesh (no rig): render the geometry
// directly, centered + scaled to a unit box, squared to a dorsal view, with pinch/drag to rotate.
//
// Acupoint markers: this asset is arbitrarily posed in its own coordinate frame, so axis-aligned
// bbox-fraction placement lands off-surface. Instead we map the VALIDATED 2D hand-atlas positions
// (the 360×440 atlas box the point data in Acupoints.swift is calibrated to) into the dorsal
// viewing plane and RAYCAST each onto the mesh surface in world space — robust to the mesh's odd
// local axes. The mapping is a small tunable affine (HandMarkerCalib); if the points read
// mirrored/rotated on device, flip one flag there (the same kind of one-line visual nudge TE3
// needed). Markers are tappable (onSelect). Shared marker/material/mesh/tap helpers live in
// SceneKitAtlas.
struct HandModel3DView: UIViewRepresentable {
    var resetToken: Int = 0                      // bump to animate the camera back to canonical
    var loading: Binding<Bool>? = nil            // reports GLB decode state to the sheet chrome
    var onSelect: (Acupoint) -> Void = { _ in }

    // Atlas→dorsal-plane mapping. After centre+scale+rotate, fingers run along world Y and the
    // dorsal face looks toward +Z (the camera). These map atlas (x,y in 360×440) → normalized (u,v)
    // in the hand's on-screen bounding box; each marker is then raycast onto the surface
    // (AtlasMarkers.screenMarker). Tweak here if the layout needs nudging. Only points whose atlas
    // (x,y) falls inside [ax/ay range] are placed — so the dorsal hand points (TE3/SI3/PC8/HT7)
    // map on, while the forearm points (PC6 y=344 / SJ5 y=320) are left to the body atlas rather
    // than fired off the hand mesh.
    enum HandMarkerCalib {
        static let flipX = false
        static let flipY = true                 // atlas y grows down (toward wrist) → world Y grows up
        // Calibrated against the CENTERED unit mesh in the chart pose (fingers up, thumb left): the
        // thumb widens the screen bbox, so the atlas x-range maps onto a WIDER virtual box (0…320)
        // to compress the ulnar column back onto the hand. Tuned via the DetailSnapshotTests render.
        static let axMin: Double = 0,   axMax: Double = 320   // atlas x range mapped onto the bbox
        static let ayMin: Double = 45,  ayMax: Double = 300   // atlas y extent of the hand
        static func contains(_ ax: Double, _ ay: Double) -> Bool {
            ax >= axMin && ax <= axMax && ay >= ayMin && ay <= ayMax
        }
        // Normalized (u,v) in ~[-0.5…0.5] — a fraction of the hand's on-screen bounding box, for the
        // camera-space marker placement (AtlasMarkers.screenMarker).
        static func uv(_ ax: Float, _ ay: Float) -> (Float, Float) {
            var u = (ax - Float(axMin)) / Float(axMax - axMin) - 0.5
            var v = (ay - Float(ayMin)) / Float(ayMax - ayMin) - 0.5
            if flipX { u = -u }
            if flipY { v = -v }
            return (u, v)
        }

        // Per-point visual nudges (in u,v) on TOP of the linear map: this mesh's splayed fingers
        // stretch the bbox upward and its ulnar border slants toward the wrist, neither of which a
        // linear atlas→bbox map can follow — and the atlas (x,y) can't move because the 2D chart is
        // calibrated to it. Same one-time-nudge philosophy as PartDetail.layout. Tuned via
        // DetailSnapshotTests' detail_hand.png / detail_hand_palm.png renders (user-reported: TE3
        // sat up on the finger bases instead of the metacarpal groove behind the knuckles).
        static let nudge: [String: SIMD2<Float>] = [
            "TE3": [0.02, -0.14],   // down off the finger bases, into the 4th/5th metacarpal groove
            "TE2": [0.04, -0.12],   // down to the ring/little web margin
            "SI3": [0.05, -0.06],   // onto the ulnar border just behind the 5th knuckle
            "HT7": [-0.10, 0.01],
            "SI4": [-0.05, 0.00],
            "LU9": [-0.10, 0.00],   // out to the RADIAL end of the palmar wrist crease
        ]

        // Final placement mapping for a hand point: linear atlas→bbox map + its visual nudge.
        static func uv(for pt: Acupoint) -> (Float, Float) {
            var (u, v) = uv(Float(pt.x), Float(pt.y))
            if let n = nudge[pt.id] { u += n.x; v += n.y }
            return (u, v)
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
        // A re-presented sheet can carry a non-zero token from its parent into a FRESH coordinator
        // (lastResetToken 0); sync here so the first updateUIView doesn't fire a spurious reset.
        context.coordinator.lastResetToken = resetToken

        // Shared cache/decode/camera scaffolding (SceneKitAtlas.installDetailMesh); this view only
        // supplies the pose + its marker placement. Chart pose: fingers up, thumb left, dorsum to
        // the camera — matches the 2D hand atlas convention, so the atlas (x,y)→(u,v) mapping lands
        // on the same anatomy.
        AtlasMarkers.installDetailMesh(resource: "hand_low_poly",
                                       euler: SCNVector3(0, 0.72, Float.pi), cameraZ: 2.3,
                                       in: scene, view: view, coordinator: context.coordinator,
                                       loading: loading) { mesh in
            placeMarkers(mesh: mesh, in: scene)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(AcuTapCoordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // The sheet's "reset view" button bumps resetToken → animate the camera home.
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.resetCamera()
        }
    }

    // Geometry-based marker placement: cast a ray from the camera through each in-range hand point's
    // (u,v) fraction of the model (AtlasMarkers.screenMarker) so the dots land on the VISIBLE hand — the
    // old world-Z raycast missed on this posed mesh, leaving the hand with no markers. Dorsal points hit
    // the near surface; palmar points (PC8/HT7) take the far (palm) surface. Pure geometry — no view timing.
    private func placeMarkers(mesh: SCNNode, in scene: SCNScene) {
        for pt in Acupoint.all where pt.region == "hand" && HandMarkerCalib.contains(pt.x, pt.y) {
            let (u, v) = HandMarkerCalib.uv(for: pt)
            if let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: u, v: v, farSide: !pt.requiresDorsal,
                                                 id: pt.id, color: UIColor(MeridianColors.color(pt.meridian)),
                                                 core: 0.022, halo: 0.04) {
                scene.rootNode.addChildNode(m)
            }
        }
    }
}
