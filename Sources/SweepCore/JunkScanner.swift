import Foundation

public struct JunkCategory: Identifiable, Sendable {
    public enum Safety: Sendable {
        /// Regenerated automatically; removing it has no lasting effect.
        case safe
        /// May contain things the user still wants: review before removing.
        case review
    }

    enum Source: Sendable {
        /// Every entry of the folder is a separate item.
        case children(URL)
        /// The folder itself is a single item, shown with a readable label.
        case whole(URL, label: String)
        /// Files of the folder with one of the given extensions.
        case files(URL, extensions: Set<String>)
    }

    public let id: String
    public let title: String
    /// What this is and what happens when it is removed, shown to the user.
    public let explanation: String
    public let symbol: String
    public let safety: Safety
    let sources: [Source]

    /// Only safe categories are selected without the user asking.
    public var preselected: Bool { safety == .safe }
}

public struct JunkResult: Identifiable, Sendable {
    public var id: String { category.id }
    public let category: JunkCategory
    public var items: [ScanItem]
    /// macOS refused to list at least one folder (Full Disk Access missing).
    public let accessDenied: Bool

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

public enum JunkScanner {
    public static func categories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [JunkCategory] {
        let lib = home.appendingPathComponent("Library")
        let xcode = lib.appendingPathComponent("Developer/Xcode")
        return [
            JunkCategory(
                id: "caches", title: "Cache delle app",
                explanation: "File temporanei che le app ricreano da sole quando servono. Eliminarli è sicuro: al massimo qualche app sarà più lenta al primo avvio.",
                symbol: "internaldrive", safety: .safe,
                sources: [.children(lib.appendingPathComponent("Caches"))]),
            JunkCategory(
                id: "logs", title: "Log e report di crash",
                explanation: "Registri di attività e diagnostica. Servono solo per indagare un problema già avvenuto.",
                symbol: "doc.text", safety: .safe,
                sources: [.children(lib.appendingPathComponent("Logs"))]),
            JunkCategory(
                id: "xcode", title: "Dati temporanei di Xcode",
                explanation: "DerivedData, simboli dei dispositivi e cache dei simulatori. Xcode li rigenera alla prossima build o al prossimo collegamento del dispositivo.",
                symbol: "hammer", safety: .safe,
                sources: [
                    .children(xcode.appendingPathComponent("DerivedData")),
                    .children(xcode.appendingPathComponent("iOS DeviceSupport")),
                    .children(xcode.appendingPathComponent("watchOS DeviceSupport")),
                    .whole(lib.appendingPathComponent("Developer/CoreSimulator/Caches"), label: "Cache dei simulatori"),
                ]),
            JunkCategory(
                id: "dev", title: "Cache degli strumenti di sviluppo",
                explanation: "Pacchetti scaricati da npm, pnpm, Bun, Gradle, Cargo e simili. Verranno riscaricati quando servono.",
                symbol: "shippingbox", safety: .safe,
                sources: [
                    .whole(home.appendingPathComponent(".npm/_cacache"), label: "Cache di npm"),
                    .whole(lib.appendingPathComponent("pnpm/store"), label: "Store di pnpm"),
                    .whole(home.appendingPathComponent(".bun/install/cache"), label: "Cache di Bun"),
                    .whole(home.appendingPathComponent(".gradle/caches"), label: "Cache di Gradle"),
                    .whole(home.appendingPathComponent(".cargo/registry/cache"), label: "Cache di Cargo"),
                    .children(home.appendingPathComponent(".cache")),
                ]),
            JunkCategory(
                id: "mail", title: "Allegati di Mail scaricati",
                explanation: "Copie locali degli allegati che hai aperto in Mail. Gli originali restano nei messaggi.",
                symbol: "paperclip", safety: .safe,
                sources: [.children(lib.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads"))]),
            JunkCategory(
                id: "installers", title: "Programmi di installazione",
                explanation: "Immagini disco e pacchetti nella cartella Download. Di solito non servono più dopo aver installato l'app, ma controlla prima di eliminarli.",
                symbol: "arrow.down.circle", safety: .review,
                sources: [.files(home.appendingPathComponent("Downloads"), extensions: ["dmg", "pkg", "xip", "iso"])]),
            JunkCategory(
                id: "archives", title: "Archivi di Xcode",
                explanation: "Build archiviate delle tue app. Contengono i simboli di debug (dSYM) delle versioni pubblicate: eliminale solo se non ti servono più.",
                symbol: "archivebox", safety: .review,
                sources: [.children(xcode.appendingPathComponent("Archives"))]),
            JunkCategory(
                id: "backups", title: "Backup di iPhone e iPad",
                explanation: "Backup locali dei tuoi dispositivi. Eliminarli è irreversibile: assicurati di avere un backup più recente o su iCloud.",
                symbol: "iphone", safety: .review,
                sources: [.children(lib.appendingPathComponent("Application Support/MobileSync/Backup"))]),
            JunkCategory(
                id: "trash", title: "Cestino",
                explanation: "File già spostati nel Cestino. Svuotarlo li elimina definitivamente e libera davvero lo spazio.",
                symbol: "trash", safety: .review,
                sources: [.children(home.appendingPathComponent(".Trash"))]),
        ]
    }

    public static func scan(_ category: JunkCategory) -> JunkResult {
        let fm = FileManager.default
        var urls: [URL] = []
        var names: [URL: String] = [:]
        var denied = false

        func list(_ dir: URL) -> [URL] {
            do {
                return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent != ".DS_Store" }
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                denied = true
            } catch {}
            return []
        }

        for source in category.sources {
            switch source {
            case .children(let dir):
                urls += list(dir)
            case .whole(let dir, let label):
                if fm.fileExists(atPath: dir.path) {
                    urls.append(dir)
                    names[dir] = label
                }
            case .files(let dir, let extensions):
                urls += list(dir).filter { extensions.contains($0.pathExtension.lowercased()) }
            }
        }
        return JunkResult(category: category, items: FileSizer.items(for: urls, names: names), accessDenied: denied)
    }
}
