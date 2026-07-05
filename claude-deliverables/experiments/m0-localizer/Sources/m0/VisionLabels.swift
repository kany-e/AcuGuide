import Foundation
import Vision
import CoreGraphics
import ImageIO

// ── Apple Vision hand-pose extraction, replicating AcuGuide's buildHand (CameraCoach.swift) ──────
// SAME detector, SAME gates (obs.confidence ≥ 0.5, per-point conf > 0.3), SAME coordinate convention
// (Vision bottom-left → top-left via y = 1 − y). NO x-mirror: dataset images are in native image
// space (mirroring is only the live selfie preview), and the COCO labels are native too.

struct DetHand {
    var points: [String: CGPoint]   // top-left normalized 0…1
    var isRight: Bool
    var confidence: Float
}

private let VISION_JOINT: [String: VNHumanHandPoseObservation.JointName] = [
    "wrist": .wrist, "thumbTip": .thumbTip, "indexTip": .indexTip, "middleTip": .middleTip,
    "ringTip": .ringTip, "pinkyTip": .littleTip, "indexMCP": .indexMCP, "middleMCP": .middleMCP,
    "ringMCP": .ringMCP, "pinkyMCP": .littleMCP,
]

func loadCGImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func detectHands(_ cg: CGImage) -> [DetHand] {
    let req = VNDetectHumanHandPoseRequest()
    req.maximumHandCount = 2
    let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
    do { try handler.perform([req]) } catch { return [] }
    var out: [DetHand] = []
    for obs in (req.results ?? []) {
        guard obs.confidence >= 0.5 else { continue }            // == buildHand usable-hand gate
        var pts: [String: CGPoint] = [:]
        for (name, jn) in VISION_JOINT {
            guard let rp = try? obs.recognizedPoint(jn), rp.confidence > 0.3 else { continue }
            pts[name] = CGPoint(x: rp.location.x, y: 1 - rp.location.y)   // bottom-left → top-left
        }
        guard pts["wrist"] != nil else { continue }
        out.append(DetHand(points: pts, isRight: obs.chirality != .left, confidence: obs.confidence))
    }
    return out
}

// ── COCO-style label loader for the acupoint annotations ────────────────────────────────────────
// Expected schema (MetaAcuPoint / COCO Annotator export): { images:[{id,file_name,width,height}],
// annotations:[{image_id, keypoints:[x,y,v, …]}], categories:[{keypoints:[names…]}] }. Acupoint
// pixel coords are returned in TOP-LEFT image space (COCO convention), keyed by file_name.
struct LabelRecord { var fileName: String; var width: Double; var height: Double; var points: [String: CGPoint] }

func loadCOCO(_ path: String) -> [String: LabelRecord]? {
    guard let data = FileManager.default.contents(atPath: path),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    let images = root["images"] as? [[String: Any]] ?? []
    let anns = root["annotations"] as? [[String: Any]] ?? []
    let cats = root["categories"] as? [[String: Any]] ?? []
    let names = (cats.first?["keypoints"] as? [String]) ?? ["LI4", "LI10", "LI11", "TE3", "TE5"]
    var byId: [Int: LabelRecord] = [:]
    for im in images {
        guard let id = (im["id"] as? Int) ?? (im["id"] as? Double).map({ Int($0) }),
              let fn = im["file_name"] as? String else { continue }
        let w = (im["width"] as? Double) ?? Double(im["width"] as? Int ?? 0)
        let h = (im["height"] as? Double) ?? Double(im["height"] as? Int ?? 0)
        byId[id] = LabelRecord(fileName: fn, width: w, height: h, points: [:])
    }
    for a in anns {
        guard let imgId = (a["image_id"] as? Int) ?? (a["image_id"] as? Double).map({ Int($0) }),
              var rec = byId[imgId], let kps = a["keypoints"] as? [Double] else { continue }
        var i = 0
        for name in names {
            if i + 2 < kps.count {
                let x = kps[i], y = kps[i + 1], v = kps[i + 2]
                if v > 0 { rec.points[name] = CGPoint(x: x, y: y) }   // pixel coords, top-left
            }
            i += 3
        }
        byId[imgId] = rec
    }
    var byName: [String: LabelRecord] = [:]
    for rec in byId.values { byName[rec.fileName] = rec }
    return byName
}
