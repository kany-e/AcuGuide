import XCTest
import SceneKit
import GLTFKit2
import simd
@testable import AcuGuide

// Renders each detailed drill-down (head / arm / foot) OFF SCREEN exactly as the app builds it
// (unitMesh → euler → studio lighting → camera → screenMarker bulges) and (a) asserts the mesh is
// centred and every marker lands within the model, and (b) writes a PNG so orientation + placement
// can be eyeballed. Pull the images with:
//   xcrun simctl get_app_container booted app.acuguide.ios data   # → <container>/Documents/detail_<id>.png
final class DetailSnapshotTests: XCTestCase {

    private func loadUnitMesh(_ resource: String, nodeName: String? = nil) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "glb") else {
            XCTFail("missing \(resource).glb in bundle"); return nil
        }
        let exp = expectation(description: "load \(resource)")
        var asset: GLTFAsset?
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
            if status == .complete { asset = maybeAsset }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
        guard let asset else { return nil }
        return AtlasMarkers.unitMesh(from: SCNScene(gltfAsset: asset), material: AtlasMarkers.meshMaterial(), nodeName: nodeName)
    }

    // World AABB of the posed mesh, the same box screenMarker derives placement from.
    private func worldAABB(_ mesh: SCNNode) -> (SIMD3<Float>, SIMD3<Float>) {
        let (lo, hi) = mesh.boundingBox
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude); var mx = -mn
        for a in [lo.x, hi.x] { for b in [lo.y, hi.y] { for c in [lo.z, hi.z] {
            let w = mesh.convertPosition(SCNVector3(a, b, c), to: nil)
            mn = simd_min(mn, SIMD3(w.x, w.y, w.z)); mx = simd_max(mx, SIMD3(w.x, w.y, w.z))
        } } }
        return (mn, mx)
    }

    func testDetailViewsPlaceMarkersOnModel() throws {
        for (id, cfg) in PartDetail.byRegion.sorted(by: { $0.key < $1.key }) {
            guard let mesh = loadUnitMesh(cfg.resource, nodeName: cfg.nodeName) else { XCTFail("no mesh for \(id)"); continue }
            let scene = SCNScene()
            scene.background.contents = UIColor(white: 0.90, alpha: 1)   // pale bg to read the silhouette
            AtlasMarkers.addStudioLighting(to: scene)
            mesh.eulerAngles = cfg.euler
            scene.rootNode.addChildNode(mesh)

            let cam = SCNNode(); cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
            cam.position = SCNVector3(0, 0, 2.4)
            scene.rootNode.addChildNode(cam)

            // unitMesh must centre the geometry at the origin (the bug that flung head/arm markers off
            // was a pivot-centred mesh whose convertPosition-derived box was off-origin). Guard it.
            let (mn, mx) = worldAABB(mesh)
            let center = (mn + mx) / 2
            XCTAssertLessThan(simd_length(center), 0.15, "\(id) mesh must be centred at the origin")

            // Every marker must land inside the model's silhouette box (small pad for the halo).
            let pad: Float = 0.12
            for pt in cfg.points {
                guard let uv = cfg.layout[pt.id] else { continue }
                guard let m = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: mesh, u: uv.x, v: uv.y,
                                                        farSide: cfg.back.contains(pt.id), id: pt.id,
                                                        color: UIColor(MeridianColors.color(pt.meridian)),
                                                        core: 0.03, halo: 0.055) else {
                    XCTFail("\(id)/\(pt.id) produced no marker"); continue }
                let p = SIMD3<Float>(Float(m.position.x), Float(m.position.y), Float(m.position.z))
                XCTAssertTrue(all(p .>= mn - pad) && all(p .<= mx + pad),
                              "\(id)/\(pt.id) marker \(p) fell outside the model box \(mn)…\(mx)")
                scene.rootNode.addChildNode(m)
            }

            let img = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil).also {
                $0.scene = scene; $0.pointOfView = cam
            }.snapshot(atTime: 0, with: CGSize(width: 660, height: 820), antialiasingMode: .multisampling4X)
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("detail_\(id).png")
            try img.pngData()!.write(to: out)
            print("SNAPSHOT wrote \(out.path)")
        }
    }
}

private extension NSObject {
    // Tiny configure-in-place helper so the renderer can be set up inline.
    func also(_ body: (Self) -> Void) -> Self { body(self); return self }
}
