import SwiftUI
import SceneKit
import simd

// Detailed 3D hand (hand_low_poly.glb by scribbletoad, CC-BY 4.0) for the hand drill-down — it has
// real fingers, unlike the body's low-poly mitten. Static mesh (no rig): render the geometry
// directly, centered + scaled to a unit box, squared to a dorsal view, with pinch/drag to rotate.
//
// Acupoint markers: this asset is arbitrarily posed in its own coordinate frame, so axis-aligned
// bbox-fraction placement lands off-surface. Each hand point's (u,v) in the dorsal viewing plane
// comes from the ONE placement registry (AcupointPlacements — Placements3D.swift) and is RAYCAST
// onto the mesh surface in world space (AtlasMarkers.screenMarker) — robust to the mesh's odd
// local axes. (This replaced a linear atlas→bbox map that 6 of 10 points had to override with
// nudges; the registry's baked values are the authored truth now.) Markers are tappable
// (onSelect). Shared marker/material/mesh/tap helpers live in SceneKitAtlas.
struct HandModel3DView: UIViewRepresentable {
    var resetToken: Int = 0                      // bump to animate the camera back to canonical
    var loading: Binding<Bool>? = nil            // reports GLB decode state to the sheet chrome
    var onSelect: (Acupoint) -> Void = { _ in }

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

    // Geometry-based marker placement: cast a ray from the camera through each registered hand
    // point's (u,v) fraction of the model (AtlasMarkers.screenMarker) so the dots land on the
    // VISIBLE hand. Dorsal points hit the near surface; palmar points take the far (palm) surface.
    // Points with no detailUV (the forearm's PC6/SJ5) are simply not placed here — they belong to
    // the full-body atlas. Pure geometry — no view timing.
    private func placeMarkers(mesh: SCNNode, in scene: SCNScene) {
        for pt in Acupoint.all where pt.region == "hand" {
            guard let p = AcupointPlacements.table[pt.id], let uv = p.detailUV else { continue }
            if let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: uv.x, v: uv.y,
                                                 farSide: p.detailFarSide,
                                                 id: pt.id, color: UIColor(MeridianColors.color(pt.meridian)),
                                                 core: 0.022, halo: 0.04) {
                scene.rootNode.addChildNode(m)
            }
        }
    }
}
