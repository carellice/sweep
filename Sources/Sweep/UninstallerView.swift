import SwiftUI
import SweepCore

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var picked: InstalledApp.ID?
    @State private var confirming = false
    @AppStorage("uninstallerSortBySize") private var sortBySize = false

    private var apps: AppsModel { model.apps }

    private var filtered: [InstalledApp] {
        let found = search.isEmpty ? apps.apps : apps.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        guard sortBySize else { return found }
        // Stable: apps not measured yet stay at the bottom, in alphabetical order.
        return found.sorted { apps.sizes[$0.url, default: -1] > apps.sizes[$1.url, default: -1] }
    }

    var body: some View {
        HSplitView {
            List(filtered, selection: $picked) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                        Text(app.version ?? app.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(apps.sizes[app.url].map(ByteFormat.string) ?? "…")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(app.id)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Ordina per", selection: $sortBySize) {
                    Text("Nome").tag(false)
                    Text("Dimensione").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                .background(.bar)
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Cerca app")
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Disinstalla app")
        .task { if apps.apps.isEmpty { await apps.load() } }
        .onChange(of: picked) { _, id in
            Task { await apps.select(apps.apps.first { $0.id == id }) }
        }
        .confirmationDialog(
            "\(model.removalMode.actionVerb): \(apps.selectedItems.count) elementi di \(apps.selected?.name ?? ""), \(ByteFormat.string(apps.selectedSize))?",
            isPresented: $confirming
        ) {
            Button(model.removalMode.actionVerb, role: .destructive) {
                Task {
                    await apps.uninstall(mode: model.removalMode)
                    model.refreshDisk()
                }
            }
        } message: {
            Text(model.removalMode.consequence)
        }
    }

    @ViewBuilder private var detail: some View {
        @Bindable var apps = apps
        VStack(spacing: 0) {
            if let result = apps.lastResult {
                ResultBanner(result: result) { apps.lastResult = nil }.padding(12)
            }
            if let app = apps.selected {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title2.bold())
                        Text(app.bundleID).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(16)

                if apps.isRunning {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("\(app.name) è in esecuzione: chiudila prima di disinstallarla.")
                        Spacer()
                        Button("Chiudi \(app.name)") { Task { await apps.quitSelected() } }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }

                List(apps.footprint) { item in
                    ItemRow(item: item, selection: $apps.selection)
                }
                .overlay { if apps.isLoading { ProgressView("Ricerca dei file collegati…") } }

                Divider()
                HStack {
                    Text("Selezionati: \(ByteFormat.string(apps.selectedSize))").font(.headline)
                    Spacer()
                    Button("Disinstalla…") { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(apps.selection.isEmpty || apps.isLoading || apps.isRunning)
                }
                .padding(12)
            } else {
                ContentUnavailableView(
                    "Scegli un'app", systemImage: "xmark.app",
                    description: Text("Sweep elenca l'app e tutti i file collegati: decidi tu cosa rimuovere."))
            }
        }
    }
}
