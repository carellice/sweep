import Foundation

/// A file or folder found by a scan, with its size on disk.
public struct ScanItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let size: Int64
    public let modified: Date?

    public init(url: URL, name: String? = nil, size: Int64, modified: Date? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.modified = modified
    }

    /// Parent folder, with the home directory abbreviated to `~`.
    public var location: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct DiskInfo: Sendable {
    public let total: Int64
    public let available: Int64
    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func current(for url: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskInfo {
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        return DiskInfo(
            total: Int64(values?.volumeTotalCapacity ?? 0),
            available: values?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
