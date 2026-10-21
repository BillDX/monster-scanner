import CryptoKit
import Foundation

/// Where model files live and how they are checked. Files sit in
/// Application Support/Models/<pack id>/, excluded from iCloud and iTunes
/// backups. A file is only ever loaded after its SHA-256 matches the pin.
nonisolated enum ModelStore {
    enum StoreError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case wrongSize(String)
        case checksumMismatch(String)

        var description: String {
            switch self {
            case .missing(let name): "\(name) is missing"
            case .wrongSize(let name): "\(name) has the wrong size"
            case .checksumMismatch(let name): "\(name) failed its SHA-256 check"
            }
        }
    }

    static func directory(for pack: ModelPack) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        var models = base.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try models.setResourceValues(values)
        let packDirectory = models.appendingPathComponent(pack.id, isDirectory: true)
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        return packDirectory
    }

    static func url(for file: ModelFile, in pack: ModelPack) throws -> URL {
        try directory(for: pack).appendingPathComponent(file.name)
    }

    static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    /// All files present with the pinned sizes (cheap; not a hash check).
    static func isInstalled(_ pack: ModelPack) -> Bool {
        pack.files.allSatisfy { file in
            guard let url = try? url(for: file, in: pack) else { return false }
            return size(of: url) == file.bytes
        }
    }

    /// Full SHA-256 check of every file. Throws on the first problem.
    @concurrent
    static func verify(_ pack: ModelPack) async throws {
        for file in pack.files {
            let url = try url(for: file, in: pack)
            guard let size = size(of: url) else { throw StoreError.missing(file.name) }
            guard size == file.bytes else { throw StoreError.wrongSize(file.name) }
            guard try sha256(of: url) == file.sha256 else { throw StoreError.checksumMismatch(file.name) }
        }
    }

    /// Streams the file through SHA-256 in 8 MB chunks.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 8 * 1024 * 1024) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func delete(_ pack: ModelPack) throws {
        let directory = try directory(for: pack)
        try FileManager.default.removeItem(at: directory)
    }

    /// Free space for large, user-requested downloads.
    static func availableBytes() -> Int64? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return try? base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}
