import Foundation

/// One downloadable file, pinned by size and SHA-256 (DECISIONS.md D-015).
nonisolated struct ModelFile: Sendable, Hashable {
    let name: String
    let url: URL
    let bytes: Int64
    let sha256: String
}

/// A model plus its vision projector.
nonisolated struct ModelPack: Sendable, Hashable {
    let id: String
    let displayName: String
    let model: ModelFile
    let projector: ModelFile

    var files: [ModelFile] { [model, projector] }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
}

nonisolated enum ModelCatalog {
    /// Official Qwen org, pinned to a repo commit.
    private static let qwenBase = "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/52d6c8ffea26cc873ac5ad116f8631268d7eb503/"

    static let qwen3VL2B = ModelPack(
        id: "qwen3-vl-2b-q4km",
        displayName: "QWEN3-VL-2B",
        model: ModelFile(
            name: "Qwen3VL-2B-Instruct-Q4_K_M.gguf",
            url: URL(string: qwenBase + "Qwen3VL-2B-Instruct-Q4_K_M.gguf")!,
            bytes: 1_107_409_952,
            sha256: "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae"
        ),
        projector: ModelFile(
            name: "mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf",
            url: URL(string: qwenBase + "mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf")!,
            bytes: 445_053_216,
            sha256: "f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82"
        )
    )

    static let current = qwen3VL2B
}
