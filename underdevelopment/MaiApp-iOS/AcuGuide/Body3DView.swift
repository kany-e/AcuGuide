import SwiftUI
import SceneKit

// Rotatable 3D body (native port of MaiApp's Body3D / three.js scene).
// Drop a `body.usdz` into the app bundle to show the real model. Converting MaiApp/model.glb
// is a manual step — glTF has no on-device/CLI importer in SceneKit, so convert it with Reality
// Converter (free, macOS) or `usdzconvert` and add the result as `body.usdz`. Without it, the
// glowing capsule placeholder is shown.
struct Body3DView: View {
    var body: some View {
        ZStack {
            Ink.parch.ignoresSafeArea()
            SceneKitBody().ignoresSafeArea()
            VStack {
                Spacer()
                Text("Drag to rotate · tap the hand tab for acupoints")
                    .font(.caption).foregroundStyle(Ink.paper.opacity(0.7)).padding(.bottom, 24)
            }
        }
    }
}

struct SceneKitBody: UIViewRepresentable {
    func makeUIView(context: Context) -> SpinSCNView {
        let view = SpinSCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true            // user can orbit/zoom
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        // Everything spins on a container node so the gentle auto-rotation and the user's drag
        // don't fight: dragging moves the CAMERA (allowsCameraControl), and the container's spin
        // is PAUSED while a touch is down (see SpinSCNView), then resumes.
        let spin = SCNNode()
        if let url = Bundle.main.url(forResource: "body", withExtension: "usdz"),
           let loaded = try? SCNScene(url: url) {
            for child in loaded.rootNode.childNodes { spin.addChildNode(child) }
        } else {
            let body = SCNNode(geometry: SCNCapsule(capRadius: 0.4, height: 2.2))
            body.geometry?.firstMaterial?.diffuse.contents = UIColor(Ink.jade)
            body.geometry?.firstMaterial?.emission.contents = UIColor(Ink.gold).withAlphaComponent(0.25)
            spin.addChildNode(body)
        }
        scene.rootNode.addChildNode(spin)
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))

        view.scene = scene
        view.spinNode = spin
        return view
    }
    func updateUIView(_ uiView: SpinSCNView, context: Context) {}
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
