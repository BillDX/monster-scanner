import Foundation

/// The app's only network code (spec section 5): downloads the pinned model
/// files over HTTPS from the official Hugging Face repo, Wi-Fi only unless
/// the player allows cellular, and checks each file's SHA-256 before keeping it.
nonisolated final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Progress: Sendable {
        let fileName: String
        /// Bytes done across the whole pack.
        let receivedBytes: Int64
        let totalBytes: Int64
        var fraction: Double { totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0 }
    }

    enum DownloadError: Error, CustomStringConvertible {
        case badStatus(Int)
        case notEnoughSpace(needed: Int64)
        case checksumMismatch(String)
        case cancelled

        var description: String {
            switch self {
            case .badStatus(let code): "the server answered \(code)"
            case .notEnoughSpace(let needed):
                "not enough free space (needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)))"
            case .checksumMismatch(let name): "\(name) failed its SHA-256 check and was deleted"
            case .cancelled: "cancelled"
            }
        }
    }

    private let lock = NSLock()
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var stagingURL: URL?
    private var currentTask: URLSessionDownloadTask?
    private var bytesBeforeCurrentFile: Int64 = 0
    private var currentFile: ModelFile?
    private var totalBytes: Int64 = 0
    private var onProgress: (@Sendable (Progress) -> Void)?
    private var isCancelled = false

    init(allowCellular: Bool) {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = allowCellular
        configuration.allowsExpensiveNetworkAccess = allowCellular
        configuration.allowsConstrainedNetworkAccess = false // respect Low Data Mode
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Downloads every missing file of `pack`, verifying each one.
    @concurrent
    func download(_ pack: ModelPack, onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        let directory = try ModelStore.directory(for: pack)
        let missing = pack.files.filter { ModelStore.size(of: directory.appendingPathComponent($0.name)) != $0.bytes }
        let needed = missing.reduce(Int64(0)) { $0 + $1.bytes }
        if let free = ModelStore.availableBytes(), free < needed + 200_000_000 {
            throw DownloadError.notEnoughSpace(needed: needed)
        }

        lock.withLock {
            self.onProgress = onProgress
            self.totalBytes = pack.totalBytes
            self.bytesBeforeCurrentFile = pack.totalBytes - needed
            self.isCancelled = false
        }

        for file in missing {
            let destination = directory.appendingPathComponent(file.name)
            let staged = try await fetch(file, stagingIn: directory)
            // Check before keeping it; a bad file is deleted, never loaded.
            let actual = try ModelStore.sha256(of: staged)
            guard actual == file.sha256 else {
                try? FileManager.default.removeItem(at: staged)
                throw DownloadError.checksumMismatch(file.name)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staged, to: destination)
            lock.withLock { bytesBeforeCurrentFile += file.bytes }
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            currentTask?.cancel()
        }
    }

    // MARK: One file

    private func fetch(_ file: ModelFile, stagingIn directory: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            lock.withLock {
                if isCancelled {
                    continuation.resume(throwing: DownloadError.cancelled)
                    return
                }
                self.continuation = continuation
                self.currentFile = file
                self.stagingURL = directory.appendingPathComponent(file.name + ".part")
                var request = URLRequest(url: file.url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let task = session.downloadTask(with: request)
                self.currentTask = task
                task.resume()
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            defer { self.continuation = nil; self.currentTask = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let (handler, progress) = lock.withLock { () -> ((@Sendable (Progress) -> Void)?, Progress) in
            (onProgress, Progress(
                fileName: currentFile?.name ?? "",
                receivedBytes: bytesBeforeCurrentFile + totalBytesWritten,
                totalBytes: totalBytes
            ))
        }
        handler?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(DownloadError.badStatus(http.statusCode)))
            return
        }
        // The temporary file disappears when this method returns: move it now.
        guard let staging = lock.withLock({ stagingURL }) else { return }
        do {
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.moveItem(at: location, to: staging)
            finish(.success(staging))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return } // success is reported by didFinishDownloadingTo
        let cancelled = lock.withLock { isCancelled }
        finish(.failure(cancelled ? DownloadError.cancelled : error))
    }
}
