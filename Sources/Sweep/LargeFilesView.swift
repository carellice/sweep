import SwiftUI
import SweepCore

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ScanItem.size, order: .reverse)]
    @State private var confirming = false

    private var large: LargeFilesModel { model.large }

    var body: some View {
        @Bindable var large = large
        VStack(spacing: 0) {
            HStack {
                Button { chooseFolder() } label: {
                    Label((large.root.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                }
                Picker("Più grandi di", selection: $large.threshold) {
                    ForEach(LargeFilesModel.thresholds, id: \.self) { Text(ByteFormat.string($0)).tag($0) }
                }
                .fixedSize()
                Toggle("Includi cartelle", isOn: $large.includeFolders)
                    .help("Elenca anche le cartelle intere che superano la soglia. La ricerca è più lenta.")
                Spacer()
                if large.isScanning {
                    ProgressView().controlSize(.small)
                    Button("Interrompi") { large.stop() }
                } else {
                    Button("Cerca") { Task { await large.scan() } }.buttonStyle(.borderedProminent)
                }
            }
            .padding(12)

            if let result = large.lastResult {
                ResultBanner(result: result) { large.lastResult = nil }.padding([.horizontal, .bottom], 12)
            }

            Table(large.items, selection: $large.selection, sortOrder: $sortOrder) {
                TableColumn("Nome", value: \.name) { item in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable().frame(width: 18, height: 18)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                TableColumn("Cartella", value: \.location) { item in
                    Text(item.location).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                TableColumn("Modificato") { item in
                    Text(item.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        .foregroundStyle(.secondary)
                }
                .width(110)
                TableColumn("Dimensione", value: \.size) { item in
                    Text(ByteFormat.string(item.size)).monospacedDigit()
                }
                .width(100)
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Mostra nel Finder") { revealInFinder(Array(urls)) }
            } primaryAction: { urls in
                revealInFinder(Array(urls))
            }
            .onChange(of: sortOrder) { _, order in large.sort(using: order) }
            .overlay {
                if large.items.isEmpty, !large.isScanning {
                    ContentUnavailableView(
                        large.hasScanned ? "Nessun elemento trovato" : "File grandi",
                        systemImage: "doc.viewfinder",
                        description: Text(large.hasScanned
                            ? "Niente supera la soglia scelta in questa cartella."
                            : "Scegli una cartella e una soglia, poi premi Cerca. Con “Includi cartelle” vedi anche le cartelle intere oltre la soglia. La Libreria e i file nascosti sono esclusi."))
                }
            }

            Divider()
            HStack {
                Text("Selezionati: \(large.selectedItems.count) elementi, \(ByteFormat.string(large.selectedSize))").font(.headline)
                Spacer()
                Button("\(model.removalMode.actionVerb)…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(large.selection.isEmpty)
            }
            .padding(12)
        }
        .navigationTitle("File grandi")
        .confirmationDialog(
            "\(model.removalMode.actionVerb): \(large.selectedItems.count) elementi, \(ByteFormat.string(large.selectedSize))?",
            isPresented: $confirming
        ) {
            Button(model.removalMode.actionVerb, role: .destructive) {
                Task {
                    await large.removeSelected(mode: model.removalMode)
                    model.refreshDisk()
                }
            }
        } message: {
            Text(model.removalMode.consequence)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = large.root
        if panel.runModal() == .OK, let url = panel.url {
            large.root = url
        }
    }
}
