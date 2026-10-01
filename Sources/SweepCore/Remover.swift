import Foundation

public enum RemovalMode: Sendable {
    /// Move to the Trash: reversible, space is freed when the Trash is emptied.
    case trash
    /// Delete immediately: irreversible.
    case permanent
}

public struct RemovalResult: Sendable {
    public struct Failure: Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let reason: String
    }

    public var mode: RemovalMode
    public var removed: [URL] = []
    public var bytes: Int64 = 0
    public var failures: [Failure] = []
}

public enum Remover {
    public static func remove(
        _ items: [ScanItem], mode: RemovalMode,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> RemovalResult {
        let fm = FileManager.default
        let trashPrefix = home.appendingPathComponent(".Trash").standardizedFileURL.path + "/"
        var result = RemovalResult(mode: mode)

        for item in items {
            guard SafetyGuard.canRemove(item.url, home: home) else {
                result.failures.append(.init(url: item.url, reason: "Percorso protetto: Sweep non lo elimina."))
                continue
            }
            // Things already in the Trash can only be deleted for good.
            let inTrash = item.url.standardizedFileURL.path.hasPrefix(trashPrefix)
            do {
                if mode == .permanent || inTrash {
                    try fm.removeItem(at: item.url)
                } else {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                }
                result.removed.append(item.url)
                result.bytes += item.size
            } catch {
                result.failures.append(.init(url: item.url, reason: error.localizedDescription))
            }
        }
        return result
    }
}
