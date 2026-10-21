// swift-tools-version: 6.0
// Mac-only probe: runs the real observation call (llama.cpp + Qwen3-VL) on
// image files, using the same engine source as the app (symlinked).
//   swift run -c release llama-probe <model.gguf> <mmproj.gguf> <image>...
import PackageDescription

let package = Package(
    name: "LlamaProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/MonsterCore")],
    targets: [
        .binaryTarget(name: "llama", path: "llama.xcframework"),
        .executableTarget(
            name: "llama-probe",
            dependencies: ["llama", .product(name: "MonsterCore", package: "MonsterCore")]
        ),
    ]
)
