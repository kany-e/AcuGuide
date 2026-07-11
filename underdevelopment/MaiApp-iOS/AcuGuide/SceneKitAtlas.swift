import SceneKit
import UIKit
import SwiftUI
import GLTFKit2
import simd

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

    // Shortest-arc rotation taking `up` onto `n`, hardened against the two degenerate cases
    // (parallel → identity, antiparallel → 180° about an arbitrary perpendicular) that make the
    // stock simd_quatf(from:to:) return NaN.
    private static func orientation(from up: simd_float3, to n: simd_float3) -> simd_quatf {
        let d = simd_dot(up, n)
        if d > 0.9999 { return simd_quatf(angle: 0, axis: simd_float3(1, 0, 0)) }
        if d < -0.9999 { return simd_quatf(angle: .pi, axis: simd_float3(1, 0, 0)) }
        return simd_quatf(angle: acos(d), axis: simd_normalize(simd_cross(up, n)))
    }

    // An acupoint that reads as PART OF THE SURFACE — a "light bulge": a glowing sphere flattened
    // along the surface normal and sunk slightly into the skin, with a soft flat halo, so it domes
    // out of the mesh instead of floating above it as a bead. Oriented to `normal`, named
    // "acu:<id>" for hit-testing. Used by the detailed hand/part drill-downs (via screenMarker).
    static func domeMarker(id: String, color: UIColor, radius: CGFloat, halo: CGFloat,
                           at pos: SCNVector3, normal: SCNVector3, depthTested: Bool = false) -> SCNNode {
        let container = SCNNode()
        container.position = pos
        container.name = "acu:" + id
        container.renderingOrder = 15
        let n = simd_normalize(simd_float3(Float(normal.x), Float(normal.y), Float(normal.z)))
        container.simdOrientation = orientation(from: simd_float3(0, 1, 0), to: n)

        // Bright core mound: flattened along the normal (local +Y) → a shallow dome, not a ball.
        // Centered ON the surface: the under-surface half is hidden by the mesh when depth-tested
        // (so the visible part is a true half-dome rising off the skin), and reads the same when not.
        let bulge = SCNSphere(radius: radius); bulge.firstMaterial = glowMat(color, 1.0, depthTested: depthTested)
        let b = SCNNode(geometry: bulge)
        b.scale = SCNVector3(1, 0.4, 1)
        container.addChildNode(b)

        // Soft wash of light around the bulge, flattened flush to the surface. It READS depth (so
        // the mesh occludes it) but never WRITES it — a translucent wash writing depth would
        // occlude its own core sphere drawn after it.
        let haloMat = glowMat(color, 0.20, depthTested: depthTested)
        haloMat.writesToDepthBuffer = false
        let glow = SCNSphere(radius: halo); glow.firstMaterial = haloMat
        let g = SCNNode(geometry: glow)
        g.scale = SCNVector3(1, 0.22, 1)
        g.renderingOrder = 14
        container.addChildNode(g)
        return container
    }

    // Studio lighting shared by the detailed hand/part drill-downs. A warm KEY + cool RIM over a
    // LOW ambient gives the flat low-poly meshes real light/shadow + a warm/cool colour gradient, so
    // the form reads and doesn't merge into one blob at grazing angles.
    // (Body3DView keeps its own softer ambient for the translucent sage figure.)
    static func addStudioLighting(to scene: SCNScene) {
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient
        amb.light?.intensity = 300; amb.light?.color = UIColor(white: 1, alpha: 1)
        scene.rootNode.addChildNode(amb)
        // Warm key from the upper-front-left (bright, shaping side).
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 950; key.light?.color = UIColor(Color(hex: "#fff2dc"))
        key.eulerAngles = SCNVector3(-Float.pi / 5, -Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)
        // Cool rim/fill from the lower-back-right so far edges separate (cool shadow side).
        let rim = SCNNode(); rim.light = SCNLight(); rim.light?.type = .directional
        rim.light?.intensity = 500; rim.light?.color = UIColor(Color(hex: "#a9c4e6"))
        rim.eulerAngles = SCNVector3(Float.pi / 7, Float.pi * 0.82, 0)
        scene.rootNode.addChildNode(rim)
    }

    // Marker placement ROBUST to the model's pose, using PURE GEOMETRY (no view/render dependency, so it
    // can't be defeated by SwiftUI layout timing). The camera sits at (0,0,cameraZ) looking at the origin,
    // so a normalized (u,v) fraction of the model's world bounding box (u→right, v→up, ~[-0.5…0.5]) gives
    // a target on the model's mid-depth plane; we cast a ray from the camera THROUGH it and take the
    // near hit (or the far hit for `farSide` palm/sole points), so the marker lands on the VISIBLE
    // surface at that screen position regardless of the model's arbitrary local axes.
    //
    // Ray-miss policy: a uv just off the silhouette used to fall back to the bbox near/far plane —
    // which looks right head-on but FLOATS beside the model once rotated (user-reported twice: LU9/
    // LU10, then more). Now a miss SNAPS to the nearest surface hit via a small spiral of nearby
    // uv offsets (closest ring first, so the visual shift stays minimal), and only if the whole
    // spiral misses does the plane fallback fire — reported via `onSurface: false`, which the
    // DetailSnapshotTests assert against, so a floater is a TEST FAILURE now, not an eyeball job.
    //
    // The ray is intersected against the mesh's OWN triangles (CPU Möller–Trumbore over the
    // geometry sources) — NOT SCNNode.hitTestWithSegment, which silently resolves ZERO hits until
    // the geometry has been through a live renderer (that made every offscreen-test marker a
    // plane fallback, and made in-app placement depend on render timing). Pure geometry: same
    // answer in the app, in tests, every time. Low-poly meshes → the brute-force cost is trivial.
    static func screenMarker(cameraZ: Float, mesh: SCNNode, u: Float, v: Float, farSide: Bool,
                             id: String, color: UIColor, core: CGFloat, halo: CGFloat)
        -> (node: SCNNode, onSurface: Bool)? {
        let (lo, hi) = mesh.boundingBox
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude); var mx = -mn
        for a in [lo.x, hi.x] { for b in [lo.y, hi.y] { for c in [lo.z, hi.z] {
            let w = mesh.convertPosition(SCNVector3(a, b, c), to: nil)
            mn = simd_min(mn, SIMD3(w.x, w.y, w.z)); mx = simd_max(mx, SIMD3(w.x, w.y, w.z))
        } } }
        let center = (mn + mx) / 2, ext = mx - mn
        guard ext.x > 1e-4, ext.y > 1e-4 else { return nil }
        let cam = SIMD3<Float>(0, 0, cameraZ)
        let tris = worldTriangles(mesh)

        // One camera-ray cast through the (u+du, v+dv) screen fraction → (hit point, hit normal).
        func cast(_ du: Float, _ dv: Float) -> (wp: SIMD3<Float>, nrm: SIMD3<Float>)? {
            let target = SIMD3<Float>(center.x + (u + du) * ext.x, center.y + (v + dv) * ext.y, center.z)
            let dir = simd_normalize(target - cam)
            let reach = simd_length(target - cam) + ext.z + 1.0
            let hits = rayHits(tris, origin: cam, dir: dir, maxT: reach)
            guard let hit = (farSide ? hits.last : hits.first) else { return nil }
            return (cam + dir * hit.t, hit.n)
        }

        let baseDir = simd_normalize(SIMD3<Float>(center.x + u * ext.x, center.y + v * ext.y, center.z) - cam)
        var wp: SIMD3<Float>; var nrm: SIMD3<Float>; var onSurface = true
        if let hit = cast(0, 0) {
            (wp, nrm) = hit
        } else if let snapped = spiralSnap(cast) {
            (wp, nrm) = snapped                       // nearest on-surface neighbour of the uv
        } else {
            // Whole spiral missed (geometry not yet render-ready, or the uv is far off the model):
            // land on the near/far AABB plane along the base camera ray so the dot still shows at
            // the (u,v) screen position. Callers/tests see onSurface == false.
            let planeZ = farSide ? mn.z : mx.z
            let t = abs(baseDir.z) > 1e-5 ? (planeZ - cam.z) / baseDir.z : 1
            wp = cam + baseDir * t
            nrm = -baseDir                            // no surface → face the camera
            onSurface = false
        }
        // Dome AWAY from the model centre so the bulge always rises off the skin (guards a facet
        // normal that faces inward or a degenerate zero normal from a grazing hit).
        if simd_length(nrm) < 1e-4 { nrm = -baseDir } else { nrm = simd_normalize(nrm) }
        if simd_dot(nrm, wp - center) < 0 { nrm = -nrm }
        // depthTested: detail-view markers are OCCLUDED by the mesh — a far-side point (sole,
        // palm, cubital crease) stays hidden until the model is rotated to face it, exactly like
        // a real feature of the surface (previously they glowed through the body).
        let node = domeMarker(id: id, color: color, radius: core, halo: halo,
                              at: SCNVector3(wp.x, wp.y, wp.z), normal: SCNVector3(nrm.x, nrm.y, nrm.z),
                              depthTested: true)
        return (node, onSurface)
    }

    // Nearest-first spiral of uv offsets (bbox-fraction units): 8 directions per ring, radius
    // growing to ~a tenth of the model. First hit wins, so a marker just off the silhouette moves
    // the least distance needed to sit ON the mesh.
    private static func spiralSnap(_ cast: (Float, Float) -> (wp: SIMD3<Float>, nrm: SIMD3<Float>)?)
        -> (wp: SIMD3<Float>, nrm: SIMD3<Float>)? {
        for r in [Float(0.02), 0.045, 0.07, 0.10] {
            for k in 0..<8 {
                let a = Float(k) * .pi / 4
                if let hit = cast(r * cos(a), r * sin(a)) { return hit }
            }
        }
        return nil
    }

    // The mesh hierarchy's triangles in the root ("world") coordinate space — the same space the
    // AABB above and the camera ray live in. Reads the CPU-side geometry sources directly, so it
    // works identically for GLB-loaded meshes and SCN primitives, rendered or not.
    private static func worldTriangles(_ node: SCNNode) -> [SIMD3<Float>] {   // flat v0,v1,v2 triples
        var tris: [SIMD3<Float>] = []
        node.enumerateHierarchy { n, _ in
            guard let geo = n.geometry, let src = geo.sources(for: .vertex).first,
                  src.componentsPerVector >= 3, src.bytesPerComponent == 4 else { return }
            var verts = [SIMD3<Float>](); verts.reserveCapacity(src.vectorCount)
            src.data.withUnsafeBytes { raw in
                for i in 0..<src.vectorCount {
                    let base = src.dataOffset + i * src.dataStride
                    guard base + 3 * src.bytesPerComponent <= raw.count else { break }
                    verts.append(SIMD3(raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                                       raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                                       raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)))
                }
            }
            let world = verts.map { p -> SIMD3<Float> in
                let w = n.convertPosition(SCNVector3(p.x, p.y, p.z), to: nil)
                return SIMD3(Float(w.x), Float(w.y), Float(w.z))
            }
            for el in geo.elements where el.primitiveType == .triangles {
                let bpi = el.bytesPerIndex
                el.data.withUnsafeBytes { raw in
                    func idx(_ k: Int) -> Int {
                        bpi == 2 ? Int(raw.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self))
                                 : Int(raw.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self))
                    }
                    for t in 0..<el.primitiveCount {
                        let a = idx(3 * t), b = idx(3 * t + 1), c = idx(3 * t + 2)
                        guard a < world.count, b < world.count, c < world.count else { continue }
                        tris.append(world[a]); tris.append(world[b]); tris.append(world[c])
                    }
                }
            }
        }
        return tris
    }

    // Möller–Trumbore over the triangle soup: every intersection along the ray, sorted near→far
    // (first = visible surface, last = the far side for palm/sole points).
    private static func rayHits(_ tris: [SIMD3<Float>], origin: SIMD3<Float>, dir: SIMD3<Float>,
                                maxT: Float) -> [(t: Float, n: SIMD3<Float>)] {
        var hits: [(t: Float, n: SIMD3<Float>)] = []
        var i = 0
        while i + 2 < tris.count {
            let v0 = tris[i], v1 = tris[i + 1], v2 = tris[i + 2]; i += 3
            let e1 = v1 - v0, e2 = v2 - v0
            let p = simd_cross(dir, e2)
            let det = simd_dot(e1, p)
            if abs(det) < 1e-8 { continue }              // parallel / degenerate
            let inv = 1 / det
            let tv = origin - v0
            let u = simd_dot(tv, p) * inv
            if u < 0 || u > 1 { continue }
            let q = simd_cross(tv, e1)
            let v = simd_dot(dir, q) * inv
            if v < 0 || u + v > 1 { continue }
            let t = simd_dot(e2, q) * inv
            if t > 1e-5, t < maxT { hits.append((t, simd_normalize(simd_cross(e1, e2)))) }
        }
        return hits.sorted { $0.t < $1.t }
    }

    // Explicit camera at distance `z` for a unit-scaled part mesh, wired as the view's POV.
    // Returns the camera node so callers can register it for the "reset view" control.
    @discardableResult
    static func installCamera(z: Float, in scene: SCNScene, for view: SCNView) -> SCNNode {
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
        cam.position = SCNVector3(0, 0, z)
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam
        view.defaultCameraController.target = SCNVector3Zero
        return cam
    }

    // Pull the first geometry out of a loaded GLB scene, re-material it, centre its pivot, and scale
    // it into a unit box. Used by the detailed part/hand drill-downs (which then orient + add
    // markers). Returns nil if the asset has no geometry.
    static func unitMesh(from gltf: SCNScene, material: SCNMaterial, nodeName: String? = nil) -> SCNNode? {
        var found: SCNGeometry? = nil
        // Multi-part GLBs (e.g. the composite body model) carry several geometry nodes; `nodeName` picks
        // the one we want (a clean foot), otherwise take the first geometry (single-mesh assets).
        if let nodeName {
            gltf.rootNode.enumerateHierarchy { n, _ in if found == nil, n.name == nodeName { found = n.geometry } }
        }
        if found == nil {
            gltf.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
        }
        guard let found else { return nil }
        let geo = found.copy() as! SCNGeometry
        geo.materials = [material]
        // Centre the geometry via a child node's POSITION, NOT via `pivot`. SceneKit's coordinate
        // conversion (convertPosition / worldTransform) — which screenMarker relies on to derive the
        // mesh's world AABB for marker placement — does NOT honour `pivot`. A pivot-centred mesh whose
        // RAW geometry sits far from its own origin (head, arm) therefore renders centred but has its
        // markers placed against a phantom, off-origin box (they flew off the model). Offsetting the
        // child position keeps render + placement in the SAME frame, so markers land on the surface.
        let inner = SCNNode(geometry: geo)
        let (lo, hi) = inner.boundingBox
        inner.position = SCNVector3(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -(lo.z + hi.z) / 2)
        let mesh = SCNNode()
        mesh.addChildNode(inner)
        let extent = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
        let s = extent > 0 ? 1.0 / extent : 1
        mesh.scale = SCNVector3(s, s, s)
        return mesh
    }

    // Resolve a hit-test to an acupoint by walking up to a node named "acu:<id>". (Body3DView keeps
    // its own variant because it also resolves meridian channels in the same pass.)
    //
    // Only the NEAREST hit decides: hitTest returns results nearest-first, so if the first thing
    // under the finger is the mesh, a depth-hidden far-side marker behind it (KI1 under the foot
    // dorsum, palm points through the dorsal hand) must NOT be tappable straight through the
    // surface. Walking further down the hit list would do exactly that. Halos are CHILDREN of the
    // marker node, so when the nearest hit is a halo the ancestor walk still resolves "acu:".
    static func acupoint(in hits: [SCNHitTestResult]) -> Acupoint? {
        guard let first = hits.first else { return nil }
        var n: SCNNode? = first.node
        while let node = n {
            if let name = node.name, name.hasPrefix("acu:") { return Acupoint.byId[String(name.dropFirst(4))] }
            n = node.parent
        }
        return nil
    }

    // Shared GLB scaffolding for the detailed drill-down views (hand + head/arm/foot). Resolves the
    // prepared unit mesh from AtlasMeshCache — or decodes the bundled GLB, prepares it via unitMesh,
    // and stores the never-parented master — then orients it, adds it to the scene, wires the
    // explicit camera (registered with the tap coordinator for "reset view"), and hands the mesh to
    // `placeMarkers`. Preserves the cache's clone-from-master semantics: every install gets a clone.
    // The loading flag is reported ASYNC so the @State write never lands inside the SwiftUI update
    // that ran makeUIView.
    static func installDetailMesh(resource: String, nodeName: String? = nil,
                                  euler: SCNVector3, cameraZ: Float,
                                  in scene: SCNScene, view: SCNView, coordinator: AcuTapCoordinator,
                                  loading: Binding<Bool>?,
                                  placeMarkers: @escaping (SCNNode) -> Void) {
        func setLoading(_ v: Bool) {
            guard let loading else { return }
            DispatchQueue.main.async { loading.wrappedValue = v }
        }
        func install(_ mesh: SCNNode) {
            mesh.eulerAngles = euler
            scene.rootNode.addChildNode(mesh)
            let cam = installCamera(z: cameraZ, in: scene, for: view)
            coordinator.registerCamera(cam)
            placeMarkers(mesh)
            setLoading(false)
        }
        let cacheKey = AtlasMeshCache.key(resource: resource, nodeName: nodeName)
        if let cached = AtlasMeshCache.mesh(for: cacheKey) {
            install(cached)
        } else if let url = Bundle.main.url(forResource: resource, withExtension: "glb") {
            setLoading(true)
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                // The handler also fires with intermediate statuses (parsing/processing) — only
                // .error is terminal; anything else non-complete just reports progress.
                guard status == .complete, let asset = maybeAsset else {
                    if status == .error { setLoading(false) }
                    return
                }
                let gltf = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    guard let mesh = unitMesh(from: gltf, material: meshMaterial(), nodeName: nodeName) else {
                        setLoading(false); return
                    }
                    AtlasMeshCache.store(mesh, for: cacheKey)
                    install(mesh.clone())
                }
            }
        }
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

// In-memory cache of prepared detail meshes (unit-scaled + materialed via unitMesh), keyed by
// "<resource>#<nodeName>". The GLB decode is slow enough to leave a re-opened sheet visibly empty,
// so repeat opens clone the cached node instead of reloading. The stored node is never parented;
// every view gets a clone() — geometry is shared (cheap) while each scene owns its own node tree,
// so SceneKit's single-parent rule is never violated. Four small meshes at most → memory stays modest.
enum AtlasMeshCache {
    private static var meshes: [String: SCNNode] = [:]
    static func key(resource: String, nodeName: String? = nil) -> String { resource + "#" + (nodeName ?? "") }
    static func mesh(for key: String) -> SCNNode? { meshes[key]?.clone() }
    static func store(_ node: SCNNode, for key: String) { meshes[key] = node }
}

// Subtle parchment spinner shown centered over an atlas view while its GLB decodes.
struct AtlasLoadingIndicator: View {
    var body: some View {
        ProgressView()
            .tint(Ink.gold)
            .padding(14)
            .background(Circle().fill(Ink.paperLight.opacity(0.9))
                .overlay(Circle().stroke(Ink.line, lineWidth: 1)))
            .allowsHitTesting(false)
            .accessibilityLabel(AppLocale.pick("模型加载中", "Loading model"))
    }
}

// Shared tap handler for the detailed-part SCNViews: hit-test → "acu:<id>" walk-up → onSelect.
// Also owns the "reset view" camera restore: allowsCameraControl mutates the POV node's transform
// directly, so re-applying the transform captured at install time is a full reset.
// (Body3DView's SceneKitBody.Coordinator stays separate — it also drives projection + meridian taps.)
final class AcuTapCoordinator: NSObject {
    weak var view: SCNView?
    let onSelect: (Acupoint) -> Void
    weak var cameraNode: SCNNode?
    private var initialCameraTransform = SCNMatrix4Identity
    var lastResetToken = 0
    init(onSelect: @escaping (Acupoint) -> Void) { self.onSelect = onSelect }

    func registerCamera(_ cam: SCNNode) {
        cameraNode = cam
        initialCameraTransform = cam.transform
    }

    // Animate the camera back to its canonical install pose (instant under Reduce Motion).
    func resetCamera() {
        guard let view = view, let cam = cameraNode else { return }
        view.pointOfView = cam
        SCNTransaction.begin()
        SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.45
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cam.transform = initialCameraTransform
        SCNTransaction.commit()
        view.defaultCameraController.target = SCNVector3Zero
    }

    @objc func handleTap(_ g: UITapGestureRecognizer) {
        guard let view = view else { return }
        let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        if let pt = AtlasMarkers.acupoint(in: hits) { onSelect(pt) }
    }
}
