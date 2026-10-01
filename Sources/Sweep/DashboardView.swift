import SwiftUI
import SweepCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack(spacing: 36) {
                    DiskRing(disk: model.disk)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Macintosh HD").font(.title2.bold())
                        Text("\(ByteFormat.string(model.disk.used)) usati · \(ByteFormat.string(model.disk.available)) liberi")
                            .foregroundStyle(.secondary)
                        Button {
                            model.pane = .junk
                            Task { await model.junk.scan() }
                        } label: {
                            Label("Avvia scansione", systemImage: "sparkles").padding(.horizontal, 8)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                    }
                }
                .padding(.top, 24)

                HStack(alignment: .top, spacing: 16) {
                    ForEach([Pane.junk, .uninstaller, .largeFiles]) { pane in
                        Button { model.pane = pane } label: { card(pane) }
                            .buttonStyle(.plain)
                    }
                }

                Text("Sweep non elimina nulla senza mostrartelo prima: ogni elemento è elencato con percorso e dimensione, e per impostazione predefinita finisce nel Cestino.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Panoramica")
        .onAppear { model.refreshDisk() }
    }

    private func card(_ pane: Pane) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: pane.symbol).font(.title).foregroundStyle(.tint)
            Text(pane.title).font(.headline)
            Text(description(pane)).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func description(_ pane: Pane) -> String {
        switch pane {
        case .junk:
            model.junk.phase == .done
                ? "\(ByteFormat.string(model.junk.totalSize)) trovati nell'ultima scansione."
                : "Cache, log, dati di sviluppo, installer e Cestino."
        case .uninstaller: "Rimuovi un'app insieme a preferenze, cache e file di supporto."
        case .largeFiles: "Trova i file che occupano più spazio nelle tue cartelle."
        case .dashboard: ""
        }
    }
}

private struct DiskRing: View {
    let disk: DiskInfo

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 16)
            Circle()
                .trim(from: 0, to: disk.usedFraction)
                .stroke(disk.usedFraction > 0.9 ? Color.red : .accentColor,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack {
                Text(disk.usedFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("occupato").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, height: 160)
    }
}
