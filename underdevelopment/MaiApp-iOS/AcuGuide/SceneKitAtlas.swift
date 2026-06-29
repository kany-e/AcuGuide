import SceneKit
import UIKit
import SwiftUI

// Shared SceneKit primitives for the 3D atlas + part drill-downs, so the marker material, the
// glowing-sphere marker node, the static-GLB mesh load, and the "acu:<id>" tap walk-up live in ONE
// place instead of being copy-pasted across Body3DView (BodyAtlas), HandModel3DView, and
// PartModel3DView.
enum AtlasMarkers {
    // Constant-shaded glow material. `depthTested` off → always on top (needed over the translucent
    // body); on → occluded by an opaque part mesh (so a sole/palm marker hides until you rotate).
    static func glowMat(_ color: UIColor, _ opacity: CGFloat, depthTested: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.transparency = opacity
        m.readsFromDepthBuffer = depthTested
        m.writesToDepthBuffer = depthTested
        return m
    }

    // A tappable acupoint marker: glowing core + softer halo, named "acu:<id>" for hit-testing.
    static func node(id: String, color: UIColor, coreRadius: CGFloat, haloRadius: CGFloat,
                     at pos: SCNVector3, depthTested: Bool = false) -> SCNNode {
        let core = SCNSphere(radius: coreRadius); core.firstMaterial = glowMat(color, 1.0, depthTested: depthTested)
        let halo = SCNSphere(radius: haloRadius); halo.firstMaterial = glowMat(color, 0.22, depthTested: depthTested)
        let node = SCNNode(geometry: core)
        let h = SCNNode(geometry: halo); h.renderingOrder = 14
        node.addChildNode(h)
        node.position = pos
        node.name = "acu:" + id
        node.renderingOrder = 15            // markers pop above the body + channels
        return node
    }

    // Soft studio lighting (ambient + warm fill) shared by the detailed hand/part drill-downs.
    // (Body3DView keeps its own softer ambient for the translucent sage figure.)
    static func addStudioLighting(to scene: SCNScene) {
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient
        amb.light?.intensity = 740; amb.light?.color = UIColor.white
        scene.rootNode.addChildNode(amb)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .directional
        fill.light?.intensity = 240; fill.light?.color = UIColor(Color(hex: "#fffaf0"))
        fill.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi / 7, 0)
        scene.rootNode.addChildNode(fill)
    }

    // Explicit camera at distance `z` for a unit-scaled part mesh, wired as the view's POV.
    static func installCamera(z: Float, in scene: SCNScene, for view: SCNView) {
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
        cam.position = SCNVector3(0, 0, z)
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam
        view.defaultCameraController.target = SCNVector3Zero
    }

    // Pull the first geometry out of a loaded GLB scene, re-material it, centre its pivot, and scale
    // it into a unit box. Used by the detailed part/hand drill-downs (which then orient + add
    // markers). Returns nil if the asset has no geometry.
    static func unitMesh(from gltf: SCNScene, material: SCNMaterial) -> SCNNode? {
        var found: SCNGeometry? = nil
        gltf.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
        guard let found else { return nil }
        let geo = found.copy() as! SCNGeometry
        geo.materials = [material]
        let mesh = SCNNode(geometry: geo)
        let (lo, hi) = mesh.boundingBox
        mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        let extent = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
        let s = extent > 0 ? 1.0 / extent : 1
        mesh.scale = SCNVector3(s, s, s)
        return mesh
    }

    // Resolve a hit-test to an acupoint by walking up to a node named "acu:<id>". (Body3DView keeps
    // its own variant because it also resolves meridian channels in the same pass.)
    static func acupoint(in hits: [SCNHitTestResult]) -> Acupoint? {
        for h in hits {
            var n: SCNNode? = h.node
            while let node = n {
                if let name = node.name, name.hasPrefix("acu:") { return Acupoint.byId[String(name.dropFirst(4))] }
                n = node.parent
            }
        }
        return nil
    }

    // The warm parchment-sage PBR material shared by the detailed hand / part drill-down meshes.
    static func meshMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.0
        m.roughness.contents = 1.0
        m.diffuse.contents = UIColor(Color(hex: "#bcae93"))
        m.emission.contents = UIColor(Color(hex: "#2c3626")); m.emission.intensity = 0.10
        m.isDoubleSided = true
        return m
    }
}

// Shared tap handler for the detailed-part SCNViews: hit-test → "acu:<id>" walk-up → onSelect.
// (Body3DView's SceneKitBody.Coordinator stays separate — it also drives projection + meridian taps.)
final class AcuTapCoordinator: NSObject {
    weak var view: SCNView?
    let onSelect: (Acupoint) -> Void
    init(onSelect: @escaping (Acupoint) -> Void) { self.onSelect = onSelect }

    @objc func handleTap(_ g: UITapGestureRecognizer) {
        guard let view = view else { return }
        let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        if let pt = AtlasMarkers.acupoint(in: hits) { onSelect(pt) }
    }
}
