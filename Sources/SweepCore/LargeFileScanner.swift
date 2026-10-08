import Foundation

public enum LargeFileScanner {
    /// A folder whose contents are still being enumerated.
    private struct OpenFolder {
        let url: URL
        let level: Int
        let modified: Date?
        /// Shown in the results once its total size is known.
        let listed: Bool
        /// False inside hidden folders and packages: their contents only add to the parents' size.
        let showsContents: Bool
        var size: Int64 = 0
    }

    /// Files of at least `minSize` bytes under `root`, largest first.
    /// Hidden files, package contents and `~/Library` are skipped: nothing
    /// in there is a document the user manages by hand.
    ///
    /// With `includeFolders`, folders (and packages) whose whole content reaches
    /// `minSize` are listed too. Their size counts hidden files as well, so the
    /// scan has to walk everything and is slower.
    public static func scan(
        root: URL, minSize: Int64, includeFolders: Bool = false, limit: Int = 500
    ) -> [ScanItem] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
            .totalFileAllocatedSizeKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys),
            options: includeFolders ? [] : [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let library = root.appendingPathComponent("Library").standardizedFileURL.path
        var items: [ScanItem] = []
        var open: [OpenFolder] = []

        // The enumeration is depth-first: an entry at `level` ends every open folder at that depth or deeper.
        func close(downTo level: Int) {
            while let folder = open.last, folder.level >= level {
                open.removeLast()
                if !open.isEmpty { open[open.count - 1].size += folder.size }
                if folder.listed, folder.size >= minSize {
                    items.append(ScanItem(url: folder.url, size: folder.size, modified: folder.modified))
                }
            }
        }

        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            close(downTo: enumerator.level)
            if url.standardizedFileURL.path == library {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let visible = (open.last?.showsContents ?? true) && values.isHidden != true

            if values.isDirectory == true {
                open.append(OpenFolder(
                    url: url, level: enumerator.level, modified: values.contentModificationDate,
                    listed: includeFolders && visible,
                    showsContents: visible && values.isPackage != true))
            } else if values.isRegularFile == true, let size = values.totalFileAllocatedSize {
                if !open.isEmpty { open[open.count - 1].size += Int64(size) }
                if visible, Int64(size) >= minSize {
                    items.append(ScanItem(url: url, size: Int64(size), modified: values.contentModificationDate))
                }
            }
        }
        close(downTo: 0)
        return Array(items.sorted { $0.size > $1.size }.prefix(limit))
    }
}
