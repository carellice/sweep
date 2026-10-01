import SwiftUI
import SweepCore

@main
struct SweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sweep", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 600)
        }
        .defaultSize(width: 1040, height: 680)

        Settings {
            SettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`), harmless in the bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(Pane.allCases, selection: $model.pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { DiskFooter(disk: model.disk) }
        } detail: {
            switch model.pane ?? .dashboard {
            case .dashboard: DashboardView()
            case .junk: JunkView()
            case .uninstaller: UninstallerView()
            case .largeFiles: LargeFilesView()
            }
        }
    }
}

private struct DiskFooter: View {
    let disk: DiskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: disk.usedFraction)
            Text("\(ByteFormat.string(disk.available)) liberi su \(ByteFormat.string(disk.total))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Elimina definitivamente invece di spostare nel Cestino", isOn: $model.deletePermanently)
            Text("Con l'opzione disattivata tutto ciò che Sweep rimuove finisce nel Cestino e può essere ripristinato. Lo spazio si libera quando svuoti il Cestino.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Apri impostazioni Accesso completo al disco…", action: openFullDiskAccessSettings)
        }
        .padding(24)
        .frame(width: 480)
    }
}
