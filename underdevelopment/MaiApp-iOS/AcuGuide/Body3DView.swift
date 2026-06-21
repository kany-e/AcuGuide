import SwiftUI
import SceneKit

// Rotatable 3D body (native port of MaiApp's Body3D / three.js scene).
// Drop a `body.usdz` into the app bundle (convert your model.glb -> .usdz with Reality
// Converter or `usdzconvert`). Falls back to a glowing capsule placeholder if absent.
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
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X

        let scene: SCNScene
        if let url = Bundle.main.url(forResource: "body", withExtension: "usdz"),
           let loaded = try? SCNScene(url: url) {
            scene = loaded
        } else {
            scene = SCNScene()
            let body = SCNNode(geometry: SCNCapsule(capRadius: 0.4, height: 2.2))
            body.geometry?.firstMaterial?.diffuse.contents = UIColor(Ink.jade)
            body.geometry?.firstMaterial?.emission.contents = UIColor(Ink.gold).withAlphaComponent(0.25)
            scene.rootNode.addChildNode(body)
        }
        // Gentle auto-rotation, like the web atlas.
        scene.rootNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))
        view.scene = scene
        return view
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
