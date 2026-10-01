import AppKit
import Observation
import SweepCore

enum Pane: String, CaseIterable, Identifiable {
    case dashboard, junk, uninstaller, largeFiles

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "Panoramica"
        case .junk: "Pulizia"
        case .uninstaller: "Disinstalla app"
        case .largeFiles: "File grandi"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .junk: "sparkles"
        case .uninstaller: "xmark.app"
        case .largeFiles: "doc.viewfinder"
        }
    }
}

@MainActor @Observable
final class AppModel {
    var pane: Pane? = .dashboard
    var disk = DiskInfo.current()
    let junk = JunkModel()
    let apps = AppsModel()
    let large = LargeFilesModel()

    /// Off by default: everything goes to the Trash and can be put back.
    var deletePermanently = UserDefaults.standard.bool(forKey: "deletePermanently") {
        didSet { UserDefaults.standard.set(deletePermanently, forKey: "deletePermanently") }
    }

    var removalMode: RemovalMode { deletePermanently ? .permanent : .trash }

    func refreshDisk() { disk = DiskInfo.current() }
}

@MainActor @Observable
final class JunkModel {
    enum Phase { case idle, scanning, done }

    private(set) var phase = Phase.idle
    private(set) var results: [JunkResult] = []
    var selection: Set<URL> = []
    var lastResult: RemovalResult?
    private(set) var isCleaning = false

    var totalSize: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var selectedItems: [ScanItem] { results.flatMap(\.items).filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var accessDenied: Bool { results.contains(where: \.accessDenied) }

    func scan() async {
        guard phase != .scanning else { return }
        phase = .scanning
        results = []
        selection = []
        lastResult = nil

        let categories = JunkScanner.categories()
        let order = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1.id, $0) })
        await withTaskGroup(of: JunkResult.self) { group in
            for category in categories {
                group.addTask { JunkScanner.scan(category) }
            }
            for await result in group where !result.items.isEmpty || result.accessDenied {
                results.append(result)
                results.sort { order[$0.id, default: 0] < order[$1.id, default: 0] }
                if result.category.preselected {
                    selection.formUnion(result.items.map(\.url))
                }
            }
        }
        phase = .done
    }

    func clean(mode: RemovalMode) async {
        let items = selectedItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        let result = await Task.detached { Remover.remove(items, mode: mode) }.value
        let removed = Set(result.removed)
        for index in results.indices {
            results[index].items.removeAll { removed.contains($0.url) }
        }
        results.removeAll { $0.items.isEmpty && !$0.accessDenied }
        selection.subtract(removed)
        lastResult = result
        isCleaning = false
    }

    /// nil = partially selected.
    func isSelected(_ result: JunkResult) -> Bool? {
        let count = result.items.count { selection.contains($0.url) }
        if count == 0 { return false }
        return count == result.items.count ? true : nil
    }

    func toggle(_ result: JunkResult) {
        let urls = result.items.map(\.url)
        if isSelected(result) == true {
            selection.subtract(urls)
        } else {
            selection.formUnion(urls)
        }
    }
}

@MainActor @Observable
final class AppsModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var selected: InstalledApp?
    private(set) var footprint: [ScanItem] = []
    private(set) var isLoading = false
    private(set) var isRunning = false
    var selection: Set<URL> = []
    var lastResult: RemovalResult?

    var selectedItems: [ScanItem] { footprint.filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func load() async {
        let own = Bundle.main.bundleIdentifier
        apps = await Task.detached { AppScanner.installedApps() }.value.filter { $0.bundleID != own }
    }

    func select(_ app: InstalledApp?) async {
        selected = app
        footprint = []
        selection = []
        guard let app else { return }
        isLoading = true
        refreshRunning()
        let items = await Task.detached { AppScanner.footprint(of: app) }.value
        // The user may have picked another app while this one was being scanned.
        guard selected == app else { return }
        footprint = items
        selection = Set(items.map(\.url))
        isLoading = false
    }

    func quitSelected() async {
        guard let selected else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: selected.bundleID).forEach { $0.terminate() }
        try? await Task.sleep(for: .seconds(1.5))
        refreshRunning()
    }

    func uninstall(mode: RemovalMode) async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isLoading = true
        let result = await Task.detached { Remover.remove(items, mode: mode) }.value
        lastResult = result
        isLoading = false
        if let selected, result.removed.contains(selected.url) {
            apps.removeAll { $0 == selected }
            await select(nil)
        } else {
            let removed = Set(result.removed)
            footprint.removeAll { removed.contains($0.url) }
            selection.subtract(removed)
        }
    }

    private func refreshRunning() {
        guard let selected else { return isRunning = false }
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: selected.bundleID).isEmpty
    }
}

@MainActor @Observable
final class LargeFilesModel {
    static let thresholds: [Int64] = [50, 100, 500, 1000].map { $0 * 1_000_000 }

    var root = FileManager.default.homeDirectoryForCurrentUser
    var threshold = thresholds[1]
    private(set) var items: [ScanItem] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false
    var selection: Set<URL> = []
    var lastResult: RemovalResult?
    private var task: Task<[ScanItem], Never>?

    var selectedItems: [ScanItem] { items.filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() async {
        task?.cancel()
        isScanning = true
        selection = []
        lastResult = nil
        let (root, threshold) = (root, threshold)
        let task = Task.detached { LargeFileScanner.scan(root: root, minSize: threshold) }
        self.task = task
        let found = await task.value
        guard !task.isCancelled else { return }
        items = found
        isScanning = false
        hasScanned = true
    }

    func stop() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    func sort(using comparators: [KeyPathComparator<ScanItem>]) {
        items.sort(using: comparators)
    }

    func removeSelected(mode: RemovalMode) async {
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        let result = await Task.detached { Remover.remove(selected, mode: mode) }.value
        let removed = Set(result.removed)
        items.removeAll { removed.contains($0.url) }
        selection.subtract(removed)
        lastResult = result
    }
}
