import XCTest
@testable import SweepCore

final class SweepCoreTests: XCTestCase {
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("sweep-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try fm.removeItem(at: home)
    }

    @discardableResult
    private func makeFile(_ path: String, bytes: Int = 8192) throws -> URL {
        let url = home.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    // MARK: SafetyGuard

    func testGuardAllowsDisposableLocations() {
        for path in ["Library/Caches/com.foo.app", "Library/Preferences/com.foo.app.plist",
                     ".npm/_cacache", ".cache", "Downloads/setup.dmg", ".Trash/old.txt"] {
            XCTAssertTrue(SafetyGuard.canRemove(home.appendingPathComponent(path), home: home), path)
        }
        XCTAssertTrue(SafetyGuard.canRemove(URL(fileURLWithPath: "/Applications/Foo.app"), home: home))
        XCTAssertTrue(SafetyGuard.canRemove(URL(fileURLWithPath: "/Library/LaunchDaemons/com.foo.plist"), home: home))
    }

    func testGuardRejectsProtectedLocations() {
        for path in ["", "Library", "Library/Caches", "Library/Application Support", "Documents", "Desktop",
                     ".Trash", ".ssh/id_ed25519", "Library/Keychains/login.keychain-db",
                     "Library/Mobile Documents/com~apple~CloudDocs/file", "Library/Caches/../../Documents"] {
            XCTAssertFalse(SafetyGuard.canRemove(home.appendingPathComponent(path), home: home), path)
        }
        for path in ["/", "/Applications", "/Library", "/Library/Preferences", "/System/Library/CoreServices",
                     "/usr/bin/swift", "/Users", "/Volumes/Disk"] {
            XCTAssertFalse(SafetyGuard.canRemove(URL(fileURLWithPath: path), home: home), path)
        }
    }

    // MARK: Remover

    func testRemoverDeletesAllowedAndRefusesProtected() throws {
        let cache = try makeFile("Library/Caches/com.foo.app/data.bin")
        let cacheDir = cache.deletingLastPathComponent()
        try makeFile("Documents/thesis.txt")
        let documents = home.appendingPathComponent("Documents")

        let result = Remover.remove(
            [ScanItem(url: cacheDir, size: 100), ScanItem(url: documents, size: 50)],
            mode: .permanent, home: home)

        XCTAssertEqual(result.removed, [cacheDir])
        XCTAssertEqual(result.bytes, 100)
        XCTAssertEqual(result.failures.map(\.url), [documents])
        XCTAssertFalse(fm.fileExists(atPath: cacheDir.path))
        XCTAssertTrue(fm.fileExists(atPath: documents.appendingPathComponent("thesis.txt").path))
    }

    func testRemoverRetriesDeniedItemsAsAdmin() throws {
        let locked = home.appendingPathComponent("Library/Caches/locked")
        let odd = try makeFile("Library/Caches/locked/it's \"odd\" $HOME.app/data.bin").deletingLastPathComponent()
        let plain = try makeFile("Library/Caches/locked/plain/data.bin").deletingLastPathComponent()
        try makeFile(".Trash/plain/older.bin")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let items = [ScanItem(url: odd, size: 10), ScanItem(url: plain, size: 5)]

        let refused = Remover.remove(items, mode: .trash, home: home, askAdmin: true) { _ in .cancelled }
        XCTAssertTrue(refused.removed.isEmpty)
        XCTAssertEqual(refused.failures.map(\.needsAdmin), [true, true])

        // Stands in for the root shell: same command, with the folder unlocked.
        let result = Remover.remove(items, mode: .trash, home: home, askAdmin: true) { command in
            try? self.fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", command]
            try? shell.run()
            shell.waitUntilExit()
            return .done
        }
        XCTAssertEqual(Set(result.removed), [odd, plain])
        XCTAssertEqual(result.bytes, 15)
        XCTAssertTrue(result.failures.isEmpty)
        let trashed = try fm.contentsOfDirectory(atPath: home.appendingPathComponent(".Trash").path)
        XCTAssertEqual(trashed.count, 3)
        XCTAssertTrue(trashed.contains("it's \"odd\" $HOME.app"))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".Trash/plain/older.bin").path))
    }

    // MARK: Sizing and junk scan

    func testFileSizerSumsFolderTree() throws {
        try makeFile("Library/Caches/a/one.bin", bytes: 8192)
        try makeFile("Library/Caches/a/nested/two.bin", bytes: 16384)
        let size = FileSizer.size(of: home.appendingPathComponent("Library/Caches/a"))
        XCTAssertGreaterThanOrEqual(size, 8192 + 16384)
    }

    func testJunkScanFindsCachesAndInstallers() throws {
        try makeFile("Library/Caches/com.foo.app/data.bin", bytes: 16384)
        try makeFile("Library/Caches/com.bar.app/data.bin", bytes: 4096)
        try makeFile("Downloads/setup.dmg")
        try makeFile("Downloads/holiday.jpg")
        try makeFile(".npm/_cacache/blob")

        let results = Dictionary(uniqueKeysWithValues:
            JunkScanner.categories(home: home).map { ($0.id, JunkScanner.scan($0)) })

        XCTAssertEqual(results["caches"]?.items.map(\.name), ["com.foo.app", "com.bar.app"])
        XCTAssertEqual(results["installers"]?.items.map(\.name), ["setup.dmg"])
        XCTAssertEqual(results["dev"]?.items.map(\.name), ["Cache di npm"])
        XCTAssertEqual(results["logs"]?.items.count, 0)
        XCTAssertFalse(results["trash"]!.category.preselected)
        for item in results.values.flatMap(\.items) {
            XCTAssertTrue(SafetyGuard.canRemove(item.url, home: home), item.url.path)
        }
    }

    // MARK: Uninstaller

    func testLeftoverMatching() {
        let id = "com.vendor.Editor"
        XCTAssertTrue(AppScanner.matches("com.vendor.Editor", bundleID: id, appName: nil))
        XCTAssertTrue(AppScanner.matches("com.vendor.editor.plist", bundleID: id, appName: nil))
        XCTAssertTrue(AppScanner.matches("com.vendor.Editor.savedState", bundleID: id, appName: nil))
        XCTAssertTrue(AppScanner.matches("ABCDE12345.com.vendor.Editor", bundleID: id, appName: nil))
        XCTAssertTrue(AppScanner.matches("Editor", bundleID: id, appName: "Editor"))

        XCTAssertFalse(AppScanner.matches("com.vendor.Editor2.plist", bundleID: id, appName: nil))
        XCTAssertFalse(AppScanner.matches("com.vendor.Other", bundleID: id, appName: nil))
        XCTAssertFalse(AppScanner.matches("Editor", bundleID: id, appName: nil))
        XCTAssertFalse(AppScanner.matches("Editor Pro", bundleID: id, appName: "Editor"))

        // A two-part identifier must not swallow the vendor's other apps.
        XCTAssertTrue(AppScanner.matches("com.vendor.plist", bundleID: "com.vendor", appName: nil))
        XCTAssertFalse(AppScanner.matches("com.vendor.Other", bundleID: "com.vendor", appName: nil))
        XCTAssertFalse(AppScanner.matches("anything", bundleID: "vendor", appName: nil))
    }

    func testFootprintCollectsSupportFiles() throws {
        let appURL = try makeFile("Applications/Editor.app/Contents/MacOS/Editor").deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try makeFile("Library/Preferences/com.vendor.Editor.plist")
        try makeFile("Library/Application Support/Editor/state.db")
        try makeFile("Library/Caches/com.vendor.Editor/blob")
        try makeFile("Library/Caches/com.other.App/blob")

        let app = InstalledApp(url: appURL, name: "Editor", bundleID: "com.vendor.Editor")
        let items = AppScanner.footprint(of: app, home: home, includeSystemLibrary: false)

        XCTAssertEqual(items.first?.url, appURL)
        XCTAssertEqual(Set(items.dropFirst().map(\.name)), ["com.vendor.Editor.plist", "Editor", "com.vendor.Editor"])
    }

    // MARK: Large files

    func testLargeFileScanRespectsThresholdAndSkipsLibrary() throws {
        try makeFile("Movies/big.mov", bytes: 300_000)
        try makeFile("Movies/small.mov", bytes: 1_000)
        try makeFile("Library/Caches/huge.bin", bytes: 300_000)

        let items = LargeFileScanner.scan(root: home, minSize: 100_000)
        XCTAssertEqual(items.map(\.name), ["big.mov"])
    }

    func testLargeFileScanListsFoldersOnRequest() throws {
        try makeFile("Movies/big.mov", bytes: 300_000)
        try makeFile("Projects/app/a.bin", bytes: 60_000)
        try makeFile("Projects/app/.git/pack", bytes: 60_000)
        try makeFile("Projects/notes.txt", bytes: 1_000)
        try makeFile("Tools/Editor.app/Contents/MacOS/Editor", bytes: 200_000)
        try makeFile("Library/Caches/huge.bin", bytes: 300_000)

        let items = LargeFileScanner.scan(root: home, minSize: 100_000, includeFolders: true)
        // Folders count their hidden content, but hidden folders and package contents are not listed.
        XCTAssertEqual(Set(items.map(\.name)), ["Movies", "big.mov", "Projects", "app", "Tools", "Editor.app"])
        let app = try XCTUnwrap(items.first { $0.name == "app" })
        XCTAssertGreaterThanOrEqual(app.size, 120_000)
        XCTAssertGreaterThan(try XCTUnwrap(items.first { $0.name == "Projects" }).size, app.size)
    }
}
