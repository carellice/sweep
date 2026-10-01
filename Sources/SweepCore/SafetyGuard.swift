import Foundation

/// Last line of defence before anything is removed: every path must pass
/// `canRemove`, whatever scanner produced it.
public enum SafetyGuard {
    /// Top-level home folders that can never be removed themselves.
    static let protectedHome: Set<String> = [
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
        "Public", "Applications", "Library", ".Trash",
    ]
    /// Home folders whose contents are never touched either.
    static let forbiddenHome: Set<String> = [".ssh", ".gnupg"]
    /// `~/Library` folders holding user data rather than disposable files.
    static let forbiddenLibrary: Set<String> = [
        "Keychains", "Mobile Documents", "CloudStorage", "Mail", "Messages",
        "Accounts", "Calendars", "Contacts", "Photos",
    ]

    public static func canRemove(
        _ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path

        func components(under root: String) -> [String]? {
            guard path.hasPrefix(root + "/") else { return nil }
            return path.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        }

        if let rel = components(under: homePath) {
            guard let first = rel.first, !forbiddenHome.contains(first) else { return false }
            if first == "Library" {
                // Only things *inside* a Library subfolder: ~/Library/Caches/foo, not ~/Library/Caches.
                return rel.count >= 3 && !forbiddenLibrary.contains(rel[1])
            }
            return rel.count > 1 || !protectedHome.contains(first)
        }
        if let rel = components(under: "/Applications") { return !rel.isEmpty }
        if let rel = components(under: "/Library") { return rel.count >= 2 }
        if let rel = components(under: "/Volumes") { return rel.count >= 2 }
        return false
    }
}
