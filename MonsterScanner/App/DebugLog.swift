import Foundation

/// On-device debug log (spec section 6): fallbacks and errors are recorded
/// here and shown on the debug screen only. Never sent anywhere, never saved.
nonisolated final class DebugLog: @unchecked Sendable {
    static let shared = DebugLog()

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let message: String
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    private let limit = 200

    func record(_ message: String) {
        lock.lock()
        storage.append(Entry(date: .now, message: message))
        if storage.count > limit { storage.removeFirst(storage.count - limit) }
        lock.unlock()
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
