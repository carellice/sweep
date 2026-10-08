import SwiftUI
import SweepCore

struct JunkView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []
    @State private var confirming = false

    private var junk: JunkModel { model.junk }

    var body: some View {
        VStack(spacing: 0) {
            switch junk.phase {
            case .idle:
                ContentUnavailableView {
                    Label("Pulizia", systemImage: "sparkles")
                } description: {
                    Text("Cerca cache, log e altri file che puoi rimuovere. Nulla viene eliminato finché non lo confermi.")
                } actions: {
                    Button("Avvia scansione") { Task { await junk.scan() } }
                        .buttonStyle(.borderedProminent)
                }
            case .scanning, .done:
                results
            }
        }
        .navigationTitle("Pulizia")
        .toolbar {
            ToolbarItem {
                Button { Task { await junk.scan() } } label: {
                    Label("Nuova scansione", systemImage: "arrow.clockwise")
                }
                .disabled(junk.phase == .scanning || junk.isCleaning)
            }
        }
        .alert(
            "\(model.removalMode.actionVerb): \(junk.selectedItems.count) elementi, \(ByteFormat.string(junk.selectedSize))?",
            isPresented: $confirming
        ) {
            Button(model.removalMode.actionVerb, role: .destructive) {
                Task {
                    await junk.clean(mode: model.removalMode)
                    model.refreshDisk()
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        let trashed = junk.selectedItems.contains { $0.url.path.contains("/.Trash/") }
        return model.removalMode.consequence
            + (trashed && model.removalMode == .trash ? " Gli elementi già nel Cestino verranno eliminati definitivamente." : "")
    }

    private var results: some View {
        @Bindable var junk = junk
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let result = junk.lastResult {
                    ResultBanner(result: result) { junk.lastResult = nil }
                }
                if junk.accessDenied {
                    FullDiskAccessHint(categories: junk.results.filter(\.accessDenied).map(\.category.title))
                }
            }
            .padding([.horizontal, .top], 12)

            List {
                ForEach(junk.results) { result in
                    DisclosureGroup(isExpanded: binding(for: result.id)) {
                        ForEach(result.items) { item in
                            ItemRow(item: item, selection: $junk.selection)
                        }
                    } label: {
                        categoryLabel(result)
                    }
                }
                if junk.phase == .scanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scansione in corso…").foregroundStyle(.secondary)
                    }
                } else if junk.results.isEmpty {
                    Text("Niente da pulire: il tuo Mac è in ordine.").foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text("Selezionati: \(ByteFormat.string(junk.selectedSize))").font(.headline)
                    Text("Trovati in totale: \(ByteFormat.string(junk.totalSize))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if junk.isCleaning { ProgressView().controlSize(.small) }
                Button("Pulisci…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(junk.selection.isEmpty || junk.phase == .scanning || junk.isCleaning)
            }
            .padding(12)
        }
    }

    private func categoryLabel(_ result: JunkResult) -> some View {
        HStack(alignment: .top) {
            CheckBox(state: junk.isSelected(result)) { junk.toggle(result) }
                .disabled(result.items.isEmpty)
            Image(systemName: result.category.symbol).frame(width: 22).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(result.category.title).font(.headline)
                    if result.category.safety == .review {
                        Text("Da controllare")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                }
                Text(result.category.explanation).font(.callout).foregroundStyle(.secondary)
                if result.accessDenied {
                    Text("Non leggibile senza l'Accesso completo al disco.").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(ByteFormat.string(result.totalSize)).monospacedDigit().font(.headline)
        }
        .padding(.vertical, 4)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }
}
