import Foundation

public enum LargeFileScanner {
    /// Files of at least `minSize` bytes under `root`, largest first.
    /// Hidden files, package contents and `~/Library` are skipped: nothing
    /// in there is a document the user manages by hand.
    public static func scan(root: URL, minSize: Int64, limit: Int = 500) -> [ScanItem] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let library = root.appendingPathComponent("Library").standardizedFileURL.path
        var items: [ScanItem] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            if url.standardizedFileURL.path == library {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize, Int64(size) >= minSize else { continue }
            items.append(ScanItem(url: url, size: Int64(size), modified: values.contentModificationDate))
        }
        return Array(items.sorted { $0.size > $1.size }.prefix(limit))
    }
}
