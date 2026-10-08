import SwiftUI
import SweepCore

func openFullDiskAccessSettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    NSWorkspace.shared.open(url)
}

func revealInFinder(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}

/// Checkbox with an optional mixed state (`nil`).
struct CheckBox: View {
    let state: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == true ? "checkmark.square.fill" : state == nil ? "minus.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(state == false ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .buttonStyle(.plain)
    }
}

/// One selectable file row, shared by the junk and uninstaller lists.
struct ItemRow: View {
    let item: ScanItem
    @Binding var selection: Set<URL>

    var body: some View {
        HStack {
            CheckBox(state: selection.contains(item.url)) {
                if selection.remove(item.url) == nil { selection.insert(item.url) }
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(item.location).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(ByteFormat.string(item.size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Mostra nel Finder") { revealInFinder([item.url]) }
        }
    }
}

/// Outcome of the last removal, including everything that could not be removed.
struct ResultBanner: View {
    let result: RemovalResult
    let dismiss: () -> Void
    @State private var showFailures = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                if !result.failures.isEmpty {
                    Button("\(result.failures.count) elementi non rimossi: mostra dettagli") { showFailures = true }
                        .buttonStyle(.link)
                }
            }
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showFailures) {
            VStack(alignment: .leading) {
                Text("Elementi non rimossi").font(.headline)
                List(result.failures) { failure in
                    VStack(alignment: .leading) {
                        Text(failure.url.path).lineLimit(1).truncationMode(.middle)
                        Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Gli elementi protetti da macOS richiedono l'Accesso completo al disco o i privilegi di amministratore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Chiudi") { showFailures = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 560, height: 380)
        }
    }

    private var summary: String {
        let size = ByteFormat.string(result.bytes)
        if result.removed.isEmpty { return "Nessun elemento rimosso." }
        return switch result.mode {
        case .trash: "\(result.removed.count) elementi (\(size)) spostati nel Cestino. Svuotalo per liberare lo spazio."
        case .permanent: "\(result.removed.count) elementi eliminati: \(size) liberati."
        }
    }
}

/// Full Disk Access only takes effect on the next launch.
func relaunchApp() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

struct FullDiskAccessHint: View {
    /// Titles of the categories macOS refused to list.
    let categories: [String]

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "lock.shield").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(categories.formatted(.list(type: .and))): serve l'Accesso completo al disco")
                    .font(.headline)
                Text("È un permesso diverso da quelli chiesti con le finestre “Sweep vuole accedere alla cartella…”: macOS non lo propone mai da solo. In Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco attiva Sweep (se non è in elenco aggiungilo con + o trascinandolo dal Finder), poi riavvia l'app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("1. Apri Impostazioni", action: openFullDiskAccessSettings)
                    Button("Mostra Sweep nel Finder") { revealInFinder([Bundle.main.bundleURL]) }
                    Button("2. Riavvia Sweep", action: relaunchApp)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension RemovalMode {
    var actionVerb: String {
        switch self {
        case .trash: "Sposta nel Cestino"
        case .permanent: "Elimina definitivamente"
        }
    }

    var consequence: String {
        switch self {
        case .trash: "Potrai ripristinare tutto dal Cestino."
        case .permanent: "L'operazione non può essere annullata."
        }
    }
}
