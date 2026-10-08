// Offline evaluation: the SHIPPED camera-coach anchors (Acupoints.swift) vs MetaAcuPoint labels.
// Usage: swift eval.swift <annotation_resized_RGB.json> <resized_RGB dir> <out.csv>
// Conventions copied from the app: HandVision.normalize (top-left), Coach.isoDist (dy / aspect),
// isoHandSize = wrist→middleMCP, per-joint confidence gate 0.3.
import Foundation
import Vision
import ImageIO

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: eval.swift <json> <imgdir> <out.csv>"); exit(2) }
let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
let images = json["images"] as! [[String: Any]]
let anns = json["annotations"] as! [[String: Any]]
let names = (json["categories"] as! [[String: Any]])[0]["keypoints"] as! [String]
var byImage: [Int: [Double]] = [:]
for a in anns { byImage[a["image_id"] as! Int] = (a["keypoints"] as! [NSNumber]).map(\.doubleValue) }

struct P { var x: Double; var y: Double }
func iso(_ a: P, _ b: P, _ aspect: Double) -> Double {
    let dx = a.x - b.x, dy = (a.y - b.y) / aspect
    return (dx * dx + dy * dy).squareRoot()
}

let joints: [(String, VNHumanHandPoseObservation.JointName)] = [
    ("wrist", .wrist), ("thumbCMC", .thumbCMC), ("thumbMP", .thumbMP), ("thumbTip", .thumbTip),
    ("indexMCP", .indexMCP), ("middleMCP", .middleMCP), ("ringMCP", .ringMCP), ("littleMCP", .littleMCP),
    ("indexTip", .indexTip), ("middleTip", .middleTip), ("ringTip", .ringTip), ("littleTip", .littleTip)]

var out = "file,avatar,side,detected,chirality,conf,handSize,"
out += joints.map { "\($0.0)_x,\($0.0)_y" }.joined(separator: ",")
out += ",te3_x,te3_y,te5_x,te5_y,li11_x,li11_y,te3_err,te3_in,sj5_err,sj5_in\n"

var n = 0, det = 0
for im in images {
    let file = im["file_name"] as! String
    let w = Double(im["width"] as! Int), h = Double(im["height"] as! Int), aspect = w / h
    let parts = file.replacingOccurrences(of: ".png", with: "").split(separator: "_")
    let avatar = String(parts[0]), side = parts[1] == "arm1" ? "right" : "left"
    guard let kp = byImage[im["id"] as! Int] else { continue }
    func label(_ name: String) -> P { let i = names.firstIndex(of: name)!; return P(x: kp[3*i] / w, y: kp[3*i+1] / h) }
    let te3 = label("te3"), te5 = label("te5"), li11 = label("li11")
    n += 1

    let url = URL(fileURLWithPath: args[2]).appendingPathComponent(file)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let req = VNDetectHumanHandPoseRequest(); req.maximumHandCount = 2
    try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([req])
    let obs = (req.results ?? []).max { $0.confidence < $1.confidence }

    var pts: [String: P] = [:]
    if let o = obs {
        for (nm, j) in joints {
            if let rp = try? o.recognizedPoint(j), rp.confidence > 0.3 {
                pts[nm] = P(x: Double(rp.location.x), y: 1 - Double(rp.location.y))   // → top-left
            }
        }
    }
    let ok = pts["wrist"] != nil && pts["middleMCP"] != nil && pts["ringMCP"] != nil && pts["littleMCP"] != nil
    var row = "\(file),\(avatar),\(side),\(ok ? 1 : 0),"
    row += obs.map { $0.chirality == .right ? "right" : ($0.chirality == .left ? "left" : "unknown") } ?? "none"
    row += ",\(obs.map { String($0.confidence) } ?? "")"
    var te3err = "", te3in = "", sj5err = "", sj5in = "", hs = ""
    if ok {
        det += 1
        let wr = pts["wrist"]!, mm = pts["middleMCP"]!, rm = pts["ringMCP"]!, lm = pts["littleMCP"]!
        let size = iso(wr, mm, aspect); hs = String(size)
        // SHIPPED TE3: 0.11·ringMCP + 0.47·pinkyMCP + 0.42·wrist, ring = 0.16·handSize
        let t = P(x: 0.11*rm.x + 0.47*lm.x + 0.42*wr.x, y: 0.11*rm.y + 0.47*lm.y + 0.42*wr.y)
        let e3 = iso(t, te3, aspect) / size
        te3err = String(e3); te3in = e3 <= 0.16 ? "1" : "0"
        // SHIPPED SJ5: 1.7·wrist − 0.7·middleMCP, ring = 0.24·handSize
        let s = P(x: 1.7*wr.x - 0.7*mm.x, y: 1.7*wr.y - 0.7*mm.y)
        let e5 = iso(s, te5, aspect) / size
        sj5err = String(e5); sj5in = e5 <= 0.24 ? "1" : "0"
    }
    row += ",\(hs),"
    row += joints.map { j in pts[j.0].map { "\($0.x),\($0.y)" } ?? "," }.joined(separator: ",")
    row += ",\(te3.x),\(te3.y),\(te5.x),\(te5.y),\(li11.x),\(li11.y),\(te3err),\(te3in),\(sj5err),\(sj5in)\n"
    out += row
    if n % 100 == 0 { FileHandle.standardError.write("\(n) images, \(det) detected\n".data(using: .utf8)!) }
}
try! out.write(toFile: args[3], atomically: true, encoding: .utf8)
print("images \(n), hand detected with all four anchor joints \(det)")
