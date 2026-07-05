// swift-tools-version:5.9
// M0 harness for the keypoint-conditioned acupoint localizer research (see
// claude-deliverables/references/acuguide_localizer_research.md). A macOS CLI that reuses Apple
// Vision (the EXACT runtime detector AcuGuide ships) to re-project the MetaAcuPoint images into our
// keypoint feature space and compare our affine anchors vs a learned linear map on TE3/TE5(=SJ5).
import PackageDescription

let package = Package(
    name: "m0",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "m0", path: "Sources/m0")
    ]
)
