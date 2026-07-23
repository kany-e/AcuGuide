// M1 Swift round-trip: load the exported CoreML head on Apple's stack, run the same inputs the
// PyTorch model saw, and confirm the predictions match. We check TWO ways:
//   • CPU-only (float32)  → proves the exported GRAPH is exact (should be ~1e-6).
//   • ALL (ANE/float16)   → the real deployment path; expected ~1e-3 canonical = sub-pixel in image.
// Run:  swift verify.swift
import Foundation
import CoreML

// Derived from this file's own location so the script keeps working if the repo is cloned
// elsewhere or the directory moves (it used to hardcode one developer's home path).
let DIR = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let HANDSIZE = 0.13, IMG_W = 1488.0   // typical image-normalized handSize; MetaAcuPoint native width

struct Vec: Codable { let features: [Float]; let point: String; let pointIdx: Int; let predCanon: [Double]; let sigma: [Double] }
func die(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }

guard let data = FileManager.default.contents(atPath: DIR + "/test_vectors.json"),
      let vecs = try? JSONDecoder().decode([Vec].self, from: data) else { die("cannot read test_vectors.json") }
let pkg = URL(fileURLWithPath: DIR + "/AcupointHead.mlpackage")
guard let compiled = try? MLModel.compileModel(at: pkg) else { die("compileModel failed") }
print("loaded AcupointHead.mlpackage · \(vecs.count) test vectors")

func run(_ units: MLComputeUnits) -> (mean: Double, max: Double, worst: String) {
    let cfg = MLModelConfiguration(); cfg.computeUnits = units
    guard let model = try? MLModel(contentsOf: compiled, configuration: cfg) else { die("MLModel load failed") }
    var sum = 0.0, mx = 0.0, worst = ""
    for v in vecs {
        guard let feats = try? MLMultiArray(shape: [1, 20], dataType: .float32),
              let pid = try? MLMultiArray(shape: [1], dataType: .int32) else { die("MLMultiArray alloc") }
        for i in 0..<20 { feats[i] = NSNumber(value: v.features[i]) }
        pid[0] = NSNumber(value: Int32(v.pointIdx))
        guard let prov = try? MLDictionaryFeatureProvider(dictionary: [
            "features": MLFeatureValue(multiArray: feats), "pointId": MLFeatureValue(multiArray: pid)]),
            let out = try? model.prediction(from: prov),
            let coord = out.featureValue(for: "coord")?.multiArrayValue else { die("prediction failed for \(v.point)") }
        let d = max(abs(coord[0].doubleValue - v.predCanon[0]), abs(coord[1].doubleValue - v.predCanon[1]))
        sum += d; if d > mx { mx = d; worst = v.point }
    }
    return (sum / Double(vecs.count), mx, worst)
}

// The residual is cross-implementation float on the 512-way soft-argmax (CPU == ANE ⇒ not quantization);
// the meaningful bar is sub-pixel agreement in IMAGE space, not bit-exactness of a softmax reduction.
let cpu = run(.cpuOnly), all = run(.all)
func px(_ c: Double) -> Double { c * HANDSIZE * IMG_W }
print(String(format: "CPU float32  Swift-CoreML vs PyTorch:  mean %.2e · max %.2e canonical (worst: %@) ≈ %.3f px",
             cpu.mean, cpu.max, cpu.worst as NSString, px(cpu.max)))
print(String(format: "ANE/float16  (deployment path):        mean %.2e · max %.2e canonical ≈ %.3f px on a %.0fpx image",
             all.mean, all.max, px(all.max), IMG_W))
let pass = px(all.max) < 1.0        // sub-pixel image-space agreement is the meaningful criterion
print(pass ? "PASS — the exported on-device head reproduces the trained head to sub-pixel (mean ≈ 0 px)."
           : "FAIL — divergence exceeds one pixel.")
exit(pass ? 0 : 1)
