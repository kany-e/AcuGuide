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
            ShanshuiBackground()
            SceneKitBody().ignoresSafeArea()
                .accessibilityHidden(true)   // 3D canvas isn't VoiceOver-inspectable; the pill is the control

            // A pulsing gold "enter hand" control. It's a labeled control (not a marker pinned to
            // the hand), so the body's auto-rotation can't leave it stranded over empty space.
            VStack {
                Spacer()
                Button(action: onEnterHand) {
                    HStack(spacing: 8) {
                        Circle().fill(Ink.gold).frame(width: 14, height: 14)
                            .scaleEffect(pulse ? 1.2 : 0.85)
                        Text(AppLocale.pick("查看手部穴位", "View hand points"))
                            .font(.subheadline).bold()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .foregroundStyle(Ink.paperLight)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Ink.gold.opacity(0.92)))
                }
                .accessibilityLabel(AppLocale.pick("查看手部穴位", "View hand acupoints"))
                .padding(.bottom, 6)

                Text(AppLocale.pick("拖动旋转身体", "Drag to rotate the body"))
                    .font(.caption).foregroundStyle(Ink.text.opacity(0.7)).padding(.bottom, 24)
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
        // allowsCameraControl synthesizes a camera that AUTO-FRAMES the scene content — an
        // explicit fixed camera failed to frame it. Default lighting guarantees the body is lit.
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()

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
                    // GLTFKit2 imports this rigged GLB with a skinner that collapses the mesh to a
                    // point (degenerate post-conversion — flattenedClone bounds are zero), so render
                    // the static bind-pose geometry directly. It is authored Z-up (lying down), so a
                    // -90° X rotation stands it upright; the camera controller frames the result.
                    var found: SCNGeometry? = nil
                    gltfScene.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
                    guard let found else { return }         // keep the capsule if there's no mesh
                    capsule.removeFromParentNode()
                    // COPY the geometry — the shared GLTFKit2 geometry ignores a replaced materials
                    // array (its appearance is driven by GLTFKit2 shader modifiers); a copy takes ours.
                    let geometry = found.copy() as! SCNGeometry
                    geometry.materials = [sageMaterial()]
                    let mesh = SCNNode(geometry: geometry)
                    // Pivot the mesh on its own bounding-box center so the pose's rotation AND the
                    // shrink below both happen around the figure's center (keeps it centered).
                    let (lo, hi) = mesh.boundingBox
                    mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
                    // Meridian channels routed along the GLB skeleton (subtle ink), in the mesh's
                    // own coordinate space so they stay glued to the body through pose + spin.
                    mesh.addChildNode(BodyAtlas.channels())
                    let pose = SCNNode()
                    pose.addChildNode(mesh)
                    pose.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)   // stand the Z-up mesh upright
                    spin.addChildNode(pose)

                    // Explicit camera (added to the ROOT, not `spin`, so it doesn't rotate with the
                    // body). An explicit pointOfView stops allowsCameraControl's auto-fit from
                    // re-framing the figure to fill the view; we place it far enough back that the
                    // figure reads as a small ink figure (~1/5 of the view), centered, with generous
                    // empty space. Pinch-zoom drives this same camera so the user can zoom into a part.
                    let radius = pose.boundingSphere.radius            // figure is centered at origin
                    let cam = SCNNode()
                    cam.camera = SCNCamera()
                    cam.camera?.fieldOfView = 50
                    cam.camera?.zNear = 0.01
                    cam.camera?.zFar = Double(radius) * 400 + 100
                    cam.position = SCNVector3(0, 0, radius * 11)        // ~1/5 of the view at fov 50
                    scene.rootNode.addChildNode(cam)
                    view.pointOfView = cam
                }
            }
        }
        return view
    }
    func updateUIView(_ uiView: SpinSCNView, context: Context) {}
}

// MARK: - Scene helpers (match Body3D.jsx's feel)

// The sage-green material from Body3D.jsx (#aebd9d, slight emissive). Uses .blinn (not
// .physicallyBased) — PBR washes to white without an environment map, while blinn renders the
// diffuse color directly under the default lighting. Matte (no specular highlight) and slightly
// translucent (≈0.85 opaque), matching the web material's roughness 0.85 / transparency 0.85.
private func sageMaterial() -> SCNMaterial {
    let mat = SCNMaterial()
    mat.lightingModel = .blinn
    mat.diffuse.contents = UIColor(Ink.bodySage)
    mat.specular.contents = UIColor(white: 1, alpha: 0.0)   // matte — kill the glossy highlight
    mat.emission.contents = UIColor(Ink.bodyEmission).withAlphaComponent(0.12)
    mat.transparency = 0.85                                  // a little see-through (ink-wash feel)
    mat.isDoubleSided = true                                 // back faces read through the translucency
    return mat
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
