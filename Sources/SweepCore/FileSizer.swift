import Foundation

public enum FileSizer {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Space actually allocated on disk by a file, or by a whole folder tree.
    /// Symbolic links are never followed.
    public static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true || values.isSymbolicLink == true {
            return allocated(values)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += allocated(v)
        }
        return total
    }

    /// Sizes many URLs in parallel, dropping the ones that take no space.
    public static func items(for urls: [URL], names: [URL: String] = [:]) -> [ScanItem] {
        guard !urls.isEmpty else { return [] }
        var slots = [ScanItem?](repeating: nil, count: urls.count)
        slots.withUnsafeMutableBufferPointer { buffer in
            let slots = UncheckedBuffer(buffer)
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                let url = urls[i]
                let size = size(of: url)
                guard size > 0 else { return }
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                slots.buffer[i] = ScanItem(url: url, name: names[url], size: size, modified: modified)
            }
        }
        return slots.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    private static func allocated(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}

/// Each iteration writes a distinct index, so sharing the buffer is safe.
private struct UncheckedBuffer<T>: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<T>
    init(_ buffer: UnsafeMutableBufferPointer<T>) { self.buffer = buffer }
}
