import SwiftUI
import SceneKit
import GLTFKit2

// Rotatable 3D body — native port of MaiApp's Body3D.jsx. Loads the SAME asset as the web app,
// model.glb, at runtime via GLTFKit2 (no usdz conversion / no drift). Sage-green material, soft
// lighting, gentle auto-rotate that yields to the user's drag, and a pulsing gold hand hotspot
// that drills into the hand acupoint map (mirrors the web onEnterHand). The capsule is shown
// only if the model is missing or fails to load.
struct Body3DView: View {
    var onEnterHand: () -> Void = {}
    @State private var pulse = false

    var body: some View {
        ZStack {
            Ink.parch.ignoresSafeArea()
            SceneKitBody().ignoresSafeArea()
                .accessibilityHidden(true)   // 3D canvas isn't VoiceOver-inspectable; hotspot is the control

            // Pulsing gold hand hotspot, anchored over the model's hand region. Tapping drills
            // into the hand map (the body→hand drill-down, not a peer tab).
            GeometryReader { geo in
                Button(action: onEnterHand) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Ink.gold.opacity(0.22))
                                .frame(width: 46, height: 46).scaleEffect(pulse ? 1.15 : 0.85)
                            Circle().stroke(Ink.gold, lineWidth: 1.5).frame(width: 30, height: 30)
                            Circle().fill(Ink.gold).frame(width: 14, height: 14)
                        }
                        Text(AppLocale.pick("手部", "Hand"))
                            .font(.caption).bold().foregroundStyle(Ink.paperLight)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Ink.gold.opacity(0.85)))
                    }
                }
                .accessibilityLabel(AppLocale.pick("查看手部穴位", "View hand acupoints"))
                .position(x: geo.size.width * 0.72, y: geo.size.height * 0.60)
            }

            VStack {
                Spacer()
                Text(AppLocale.pick("拖动旋转 · 点按手部查看穴位",
                                    "Drag to rotate · tap the hand to view acupoints"))
                    .font(.caption).foregroundStyle(Ink.paper.opacity(0.7)).padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct SceneKitBody: UIViewRepresentable {
    func makeUIView(context: Context) -> SpinSCNView {
        let view = SpinSCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true            // user can orbit/zoom
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        addLights(to: scene)
        addCamera(to: scene, on: view)

        // Everything spins on a container node so the gentle auto-rotation and the user's drag
        // don't fight: dragging moves the CAMERA (allowsCameraControl), and the container's spin
        // is PAUSED while a touch is down (see SpinSCNView).
        let spin = SCNNode()
        scene.rootNode.addChildNode(spin)
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))

        // Capsule placeholder shown until/unless the real model loads.
        let capsule = makeCapsule()
        spin.addChildNode(capsule)

        view.scene = scene
        view.spinNode = spin

        // Load the real GLB asynchronously; swap in on success, keep the capsule otherwise.
        if let url = Bundle.main.url(forResource: "model", withExtension: "glb") {
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                guard status == .complete, let asset = maybeAsset else { return }
                let gltfScene = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    capsule.removeFromParentNode()
                    let model = SCNNode()
                    for child in gltfScene.rootNode.childNodes { model.addChildNode(child) }
                    applySageMaterial(to: model)
                    centerAndScale(model, targetHeight: 2.2)
                    spin.addChildNode(model)
                }
            }
        }
        return view
    }
    func updateUIView(_ uiView: SpinSCNView, context: Context) {}
}

// MARK: - Scene helpers (match Body3D.jsx's feel)

private func addCamera(to scene: SCNScene, on view: SCNView) {
    let cam = SCNNode()
    cam.camera = SCNCamera()
    cam.camera?.fieldOfView = 42                  // matches the web Canvas fov
    cam.camera?.zNear = 0.01
    cam.position = SCNVector3(0, 0, 3.2)
    cam.look(at: SCNVector3(0, 0, 0))
    scene.rootNode.addChildNode(cam)
    view.pointOfView = cam
}

private func addLights(to scene: SCNScene) {
    func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ hex: String) -> SCNLight {
        let l = SCNLight(); l.type = type; l.intensity = intensity; l.color = UIColor(Color(hex: hex)); return l
    }
    let ambient = SCNNode(); ambient.light = light(.ambient, 520, "#cdd2c4")
    scene.rootNode.addChildNode(ambient)

    let key = SCNNode(); key.light = light(.directional, 760, "#fffaf0")
    key.position = SCNVector3(2.5, 4, 3); key.look(at: SCNVector3(0, 0, 0))
    scene.rootNode.addChildNode(key)

    let fill = SCNNode(); fill.light = light(.directional, 300, "#dfe6ea")
    fill.position = SCNVector3(-2.5, 2, -1.5); fill.look(at: SCNVector3(0, 0, 0))
    scene.rootNode.addChildNode(fill)
}

// Override every mesh to the sage-green material from Body3D.jsx (#aebd9d, slight emissive).
private func applySageMaterial(to node: SCNNode) {
    let mat = SCNMaterial()
    mat.lightingModel = .physicallyBased
    mat.diffuse.contents = UIColor(Color(hex: "#aebd9d"))
    mat.roughness.contents = 0.85
    mat.metalness.contents = 0.0
    mat.emission.contents = UIColor(Color(hex: "#2c3626")).withAlphaComponent(0.12)
    node.enumerateHierarchy { n, _ in
        if let geo = n.geometry { geo.materials = geo.materials.map { _ in mat } }
    }
}

// Center the model at the origin and scale it to a target height (in scene units).
private func centerAndScale(_ node: SCNNode, targetHeight: Float) {
    guard let (minB, maxB) = worldBoundingBox(of: node) else { return }
    let size = SCNVector3(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
    let height = max(size.y, 0.0001)
    let scale = targetHeight / height
    node.scale = SCNVector3(scale, scale, scale)
    let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
    node.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
}

// Robust bounding box over a hierarchy (SCNNode.boundingBox covers only the node's own geometry).
private func worldBoundingBox(of root: SCNNode) -> (SCNVector3, SCNVector3)? {
    var has = false
    var mn = SCNVector3(Float.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
    var mx = SCNVector3(-Float.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
    root.enumerateHierarchy { n, _ in
        guard n.geometry != nil else { return }
        let (lo, hi) = n.boundingBox
        let corners = [
            SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, lo.y, lo.z),
            SCNVector3(lo.x, hi.y, lo.z), SCNVector3(hi.x, hi.y, lo.z),
            SCNVector3(lo.x, lo.y, hi.z), SCNVector3(hi.x, lo.y, hi.z),
            SCNVector3(lo.x, hi.y, hi.z), SCNVector3(hi.x, hi.y, hi.z),
        ]
        for c in corners {
            let w = root.convertPosition(c, from: n)
            mn = SCNVector3(min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z))
            mx = SCNVector3(max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z))
            has = true
        }
    }
    return has ? (mn, mx) : nil
}

private func makeCapsule() -> SCNNode {
    let body = SCNNode(geometry: SCNCapsule(capRadius: 0.4, height: 2.2))
    body.geometry?.firstMaterial?.diffuse.contents = UIColor(Ink.jade)
    body.geometry?.firstMaterial?.emission.contents = UIColor(Ink.gold).withAlphaComponent(0.25)
    return body
}

// Pauses the auto-rotation while the user is interacting, so it never fights the drag.
final class SpinSCNView: SCNView {
    weak var spinNode: SCNNode?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event); spinNode?.isPaused = true
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event); spinNode?.isPaused = false
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event); spinNode?.isPaused = false
    }
}
