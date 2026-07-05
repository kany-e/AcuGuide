import SwiftUI
import AVFoundation
import Vision
import CoreImage

// M3 label-capture harness. Collect OWNED expert labels for the 8 keypoint-coached hand points: freeze a
// live front-camera frame, tap the TRUE acupoint on the mirrored preview, and store (Vision joints +
// per-joint confidence + chirality + handSize → clicked target) in the EXACT normalized top-left space
// weightedTarget outputs — so there is zero reprojection error and zero train/serve skew. Because the
// head is keypoint-conditioned (not image-native), the joints ARE the training input; the frame image is
// optional provenance only. Records append to Documents/acuguide_labels/labels.jsonl. See the localizer
// research §6 Tier-2 / roadmap M3, and [[acuguide-source-upgrade]].

// One labeled frame. Joints/target are normalized TOP-LEFT, mirrored to the preview (same as buildHand).
struct LabelRecord: Codable {
    let v: Int                          // schema version
    let pointId: String
    let chirality: String               // "left" | "right" | "unknown" (Vision handedness)
    let handSize: Double                // |middleMCP − wrist|, normalized
    let joints: [String: [Double]]      // jointKey → [x, y]
    let confidence: [String: Double]    // jointKey → Vision confidence
    let target: [Double]                // expert-clicked true acupoint [x, y]
    let affine: [Double]?               // current anchor prediction [x, y] (delta reference); nil if unresolved
    let mirrored: Bool
    let ts: Double                      // unix seconds
    let session: String                 // capture-session UUID
    let image: String?                  // relative img/<uuid>.jpg if a frame was saved, else nil
}

// Append-only JSONL store (+ optional frame JPEGs) under Documents/acuguide_labels/.
final class LabelStore: ObservableObject {
    static let shared = LabelStore()
    @Published private(set) var count = 0
    @Published private(set) var perPoint: [String: Int] = [:]

    let dir: URL
    private let imgDir: URL
    private let jsonlURL: URL
    private let q = DispatchQueue(label: "app.acuguide.labelstore", qos: .utility)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("acuguide_labels", isDirectory: true)
        imgDir = dir.appendingPathComponent("img", isDirectory: true)
        jsonlURL = dir.appendingPathComponent("labels.jsonl")
        try? FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        recount()
    }

    var jsonlPath: String { jsonlURL.path }

    private func recount() {
        q.async {
            var total = 0, per: [String: Int] = [:]
            if let s = try? String(contentsOf: self.jsonlURL, encoding: .utf8) {
                let dec = JSONDecoder()
                for line in s.split(separator: "\n") {
                    guard let d = line.data(using: .utf8), let rec = try? dec.decode(LabelRecord.self, from: d) else { continue }
                    total += 1; per[rec.pointId, default: 0] += 1
                }
            }
            DispatchQueue.main.async { self.count = total; self.perPoint = per }
        }
    }

    func append(_ rec: LabelRecord, image: UIImage?) {
        q.async {
            if let image, let name = rec.image, let jpg = image.jpegData(compressionQuality: 0.8) {
                try? jpg.write(to: self.imgDir.appendingPathComponent(name))
            }
            if let data = try? JSONEncoder().encode(rec) {
                var line = data; line.append(0x0A)   // newline-delimited
                if let h = try? FileHandle(forWritingTo: self.jsonlURL) {
                    defer { try? h.close() }
                    h.seekToEndOfFile(); h.write(line)
                } else {
                    try? line.write(to: self.jsonlURL)   // first record creates the file
                }
            }
            DispatchQueue.main.async { self.count += 1; self.perPoint[rec.pointId, default: 0] += 1 }
        }
    }
}

// Front-camera capture for labeling: publishes the most-confident hand (+ confidence) every frame, and
// on request freezes ONE frame to a still (image + the hand from that same frame) so the expert can tap
// precisely. Mirrors CameraCoach's validated front-camera session config; hand-building is shared via
// HandVision (zero skew).
final class LabelCaptureCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Frozen { let image: UIImage; let hand: Hand?; let conf: [HandJoint: Float] }

    let session = AVCaptureSession()
    let mirrored = true                                  // front-camera selfie preview
    @Published var hand: Hand? = nil
    @Published var confidence: [HandJoint: Float] = [:]
    @Published var frameAspect: CGFloat = 9.0 / 16.0
    @Published var frozen: Frozen? = nil

    private var lastAspect: CGFloat = 0
    private var freezeRequested = false                  // queue-confined
    private let queue = DispatchQueue(label: "app.acuguide.labelcamera")
    private let ciContext = CIContext()
    private var videoConnection: AVCaptureConnection?
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest(); r.maximumHandCount = 1; return r
    }()

    override init() { super.init(); queue.async { [weak self] in self?.configure() } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            videoConnection = conn
            conn.forcePortrait()          // upright portrait buffers; data output stays un-mirrored
            conn.setMirrored(false)
        }
        session.commitConfiguration()
    }

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func requestFreeze() { queue.async { self.freezeRequested = true } }
    func resume() { frozen = nil }

    private func visionOrientation() -> CGImagePropertyOrientation {
        guard let conn = videoConnection else { return .up }
        if #available(iOS 17.0, *) {
            switch Int(conn.videoRotationAngle.rounded()) {
            case 90: return .up; case 0: return .right; case 180: return .left; case 270: return .down
            default: return .up
            }
        } else {
            switch conn.videoOrientation {
            case .portrait: return .up; case .landscapeRight: return .right
            case .landscapeLeft: return .left; case .portraitUpsideDown: return .down
            @unknown default: return .up
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        let aspect = CGFloat(min(w, h)) / CGFloat(max(w, h))
        if abs(aspect - lastAspect) > 0.001 { lastAspect = aspect; DispatchQueue.main.async { self.frameAspect = aspect } }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: visionOrientation(), options: [:])
        try? handler.perform([request])
        let obs = (request.results ?? []).max { $0.confidence < $1.confidence }   // most-confident hand
        let sample = obs.flatMap { HandVision.sample($0, flipX: mirrored) }
        let hand = (obs != nil && sample != nil) ? Hand(points: sample!.points, chirality: obs!.chirality) : nil
        let conf = sample?.confidence ?? [:]

        if freezeRequested {
            freezeRequested = false
            // Portrait-upright buffer → mirror to match the selfie preview (so image + joints + tap all
            // share the mirrored-preview coordinate space).
            let ci = CIImage(cvPixelBuffer: pixel).oriented(mirrored ? .upMirrored : .up)
            let image = ciContext.createCGImage(ci, from: ci.extent).map { UIImage(cgImage: $0) }
            DispatchQueue.main.async {
                self.hand = hand; self.confidence = conf
                if let image { self.frozen = Frozen(image: image, hand: hand, conf: conf) }
            }
        } else {
            DispatchQueue.main.async { self.hand = hand; self.confidence = conf }
        }
    }
}

// The capture screen: pick a point → aim → Capture (freeze) → tap the true spot → Save. The affine
// anchor is drawn as a hollow reference ring so the expert clicks the CORRECTION.
struct LabelCaptureView: View {
    @StateObject private var cam = LabelCaptureCamera()
    @ObservedObject private var store = LabelStore.shared
    @State private var pointId = ShadowLocalizer.points.first ?? "TE3"
    @State private var tapN: CGPoint? = nil            // clicked target, normalized top-left
    @State private var saveFrames = true
    @State private var session = UUID().uuidString

    private var point: Acupoint { Acupoint.byId[pointId] ?? Acupoint.all[0] }
    private var anchors: [AnchorWeight] { point.mediapipeTarget?.anchors ?? [] }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let f = cam.frozen {
                    Image(uiImage: f.image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .allowsHitTesting(false)
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded {
                            tapN = locatorInverseFill($0.location, in: geo.size, frameAspect: cam.frameAspect)
                        })
                    drawing(hand: f.hand, size: geo.size, showTap: true)
                } else {
                    CameraPreview(session: cam.session, mirrored: cam.mirrored).allowsHitTesting(false)
                    drawing(hand: cam.hand, size: geo.size, showTap: false)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar.padding(.top, 4) }
        .overlay(alignment: .bottom) { bottomBar.padding(.bottom, 8) }
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
        .navigationTitle("Label capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Non-hittable drawing layer: hand joints (white), affine reference ring (meridian colour), tap crosshair (gold).
    private func drawing(hand: Hand?, size: CGSize, showTap: Bool) -> some View {
        ZStack {
            if let h = hand {
                ForEach(HandVision.joints.filter { h.points[$0] != nil }, id: \.self) { j in
                    Circle().fill(.white.opacity(0.55)).frame(width: 6, height: 6)
                        .position(locatorMapFill(h.points[j]!, in: size, frameAspect: cam.frameAspect))
                }
                if let a = h.weightedTarget(anchors) {
                    Circle().stroke(MeridianColors.color(point.meridian), lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .position(locatorMapFill(a, in: size, frameAspect: cam.frameAspect))
                }
            }
            if showTap, let t = tapN {
                let p = locatorMapFill(t, in: size, frameAspect: cam.frameAspect)
                ZStack {
                    Circle().stroke(Ink.gold, lineWidth: 2).frame(width: 26, height: 26)
                    Circle().fill(Ink.gold).frame(width: 6, height: 6)
                }.position(p)
            }
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Menu {
                ForEach(ShadowLocalizer.points, id: \.self) { id in
                    Button { pointId = id; tapN = nil } label: {
                        Label("\(id)  ·  \(store.perPoint[id] ?? 0)", systemImage: id == pointId ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(pointId).font(.headline)
                    Text("\(store.perPoint[pointId] ?? 0)").font(.subheadline).foregroundStyle(Ink.gold)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.45)))
            }
            Spacer()
            Text("total \(store.count)").font(.subheadline).foregroundStyle(Ink.paper.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.45)))
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var bottomBar: some View {
        if let f = cam.frozen {
            VStack(spacing: 8) {
                Text(f.hand == nil ? "No hand detected — retake"
                                   : (tapN == nil ? "Tap the true \(pointId) on the frame" : "Ready to save"))
                    .font(.subheadline).foregroundStyle(f.hand == nil ? Ink.terracotta : Ink.paper)
                HStack(spacing: 14) {
                    Button("Retake") { tapN = nil; cam.resume() }.buttonStyle(.bordered).tint(.white)
                    Button("Save") { saveLabel(f) }
                        .buttonStyle(.borderedProminent).tint(Ink.gold)
                        .disabled(f.hand == nil || tapN == nil)
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.5)))
            .padding(.horizontal)
        } else {
            VStack(spacing: 10) {
                Toggle("Save frame images (provenance)", isOn: $saveFrames)
                    .font(.footnote).foregroundStyle(Ink.paper).tint(Ink.gold)
                    .padding(.horizontal, 20)
                Button { cam.requestFreeze() } label: {
                    Text("Capture").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Ink.gold)
                .disabled(cam.hand == nil)
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.45)))
            .padding(.horizontal)
        }
    }

    private func saveLabel(_ f: LabelCaptureCamera.Frozen) {
        guard let h = f.hand, let t = tapN else { return }
        let name = saveFrames ? UUID().uuidString + ".jpg" : nil
        let joints = Dictionary(uniqueKeysWithValues: h.points.map { ($0.key.key, [Double($0.value.x), Double($0.value.y)]) })
        let conf = Dictionary(uniqueKeysWithValues: f.conf.map { ($0.key.key, Double($0.value)) })
        let rec = LabelRecord(
            v: 1, pointId: pointId, chirality: chiralityKey(h.chirality),
            handSize: Double(h.handSize), joints: joints, confidence: conf,
            target: [Double(t.x), Double(t.y)],
            affine: h.weightedTarget(anchors).map { [Double($0.x), Double($0.y)] },
            mirrored: cam.mirrored, ts: Date().timeIntervalSince1970, session: session, image: name)
        store.append(rec, image: saveFrames ? f.image : nil)
        tapN = nil
        cam.resume()
    }

    private func chiralityKey(_ c: VNChirality) -> String {
        switch c {
        case .left: return "left"
        case .right: return "right"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}
