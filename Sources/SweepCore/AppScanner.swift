import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String?

    public init(url: URL, name: String, bundleID: String, version: String? = nil) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
    }
}

public enum AppScanner {
    public static func installedApps(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [URL: InstalledApp] = [:]

        func visit(_ dir: URL, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries {
                if entry.pathExtension == "app" {
                    // Apps living on the sealed system volume cannot be removed.
                    guard !entry.resolvingSymlinksInPath().path.hasPrefix("/System"),
                          let app = app(at: entry) else { continue }
                    apps[entry] = app
                } else if depth > 0, (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(entry, depth: depth - 1)
                }
            }
        }

        visit(URL(fileURLWithPath: "/Applications"), depth: 1)
        visit(home.appendingPathComponent("Applications"), depth: 1)
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func app(at url: URL) -> InstalledApp? {
        guard let info = Bundle(url: url)?.infoDictionary,
              let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { return nil }
        return InstalledApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String
        )
    }

    /// The app bundle plus every support file that belongs to it.
    public static func footprint(
        of app: InstalledApp,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeSystemLibrary: Bool = true
    ) -> [ScanItem] {
        let fm = FileManager.default
        // (folder, whether a folder named like the app also counts)
        var places: [(String, Bool)] = [
            ("Application Support", true), ("Caches", true), ("Logs", true),
            ("Preferences", false), ("Preferences/ByHost", false),
            ("Containers", false), ("Group Containers", false),
            ("Application Scripts", false), ("Saved Application State", false),
            ("HTTPStorages", false), ("WebKit", false), ("Cookies", false),
            ("LaunchAgents", false),
        ]
        var roots = [home.appendingPathComponent("Library")]
        if includeSystemLibrary {
            roots.append(URL(fileURLWithPath: "/Library"))
            places += [("LaunchDaemons", false), ("PrivilegedHelperTools", false)]
        }

        var found: [URL] = []
        for root in roots {
            for (place, byName) in places {
                let dir = root.appendingPathComponent(place)
                guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                found += entries.filter {
                    matches($0.lastPathComponent, bundleID: app.bundleID, appName: byName ? app.name : nil)
                }
            }
        }

        let leftovers = FileSizer.items(for: found).filter { SafetyGuard.canRemove($0.url, home: home) }
        let bundle = ScanItem(url: app.url, size: FileSizer.size(of: app.url))
        return [bundle] + leftovers
    }

    /// Whether a file name belongs to the app. Deliberately conservative:
    /// a false negative leaves a small file behind, a false positive deletes
    /// another app's data.
    static func matches(_ fileName: String, bundleID: String, appName: String?) -> Bool {
        let name = fileName.lowercased()
        let id = bundleID.lowercased()
        let parts = id.split(separator: ".")
        guard parts.count >= 2 else { return false }

        if name == id { return true }
        if name.hasPrefix(id + ".") {
            // "com.vendor" alone would also match every other app of the vendor,
            // so short identifiers only match well-known file suffixes.
            if parts.count >= 3 { return true }
            let rest = name.dropFirst(id.count + 1)
            return ["plist", "savedstate", "binarycookies"].contains(String(rest))
        }
        // Group containers are prefixed with the team identifier.
        if parts.count >= 3, name.hasSuffix("." + id) { return true }

        if let appName = appName?.lowercased(), appName.count >= 3 {
            return name == appName
        }
        return false
    }
}
