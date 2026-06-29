import SwiftUI
import SceneKit
import GLTFKit2

// Detailed 3D hand (hand_low_poly.glb by scribbletoad, CC-BY 4.0) for the hand drill-down — it has
// real fingers, unlike the body's low-poly mitten. Static mesh (no rig): render the geometry
// directly, centered + scaled to a unit box, squared to a dorsal view, with pinch/drag to rotate.
//
// NOTE: per-knuckle 3D acupoint markers are intentionally NOT auto-placed here — this asset is
// arbitrarily posed within its own coordinate frame (its local axes are not the anatomical
// dorsal/long axes), so bbox-fraction and axis-aligned-raycast placement land off-surface. Precise
// 3D markers need either a cleanly-posed hand mesh or interactive placement; the point list +
// the validated TE3 "Practice with camera" path are surfaced in the sheet instead.
struct HandModel3DView: UIViewRepresentable {
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
        return view
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
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
