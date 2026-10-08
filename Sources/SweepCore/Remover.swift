import Foundation

public enum RemovalMode: Sendable {
    /// Move to the Trash: reversible, space is freed when the Trash is emptied.
    case trash
    /// Delete immediately: irreversible.
    case permanent
}

public struct RemovalResult: Sendable {
    public struct Failure: Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let reason: String
        /// macOS refused for lack of permissions: worth retrying as administrator.
        public var needsAdmin = false
    }

    public var mode: RemovalMode
    public var removed: [URL] = []
    public var bytes: Int64 = 0
    public var failures: [Failure] = []
}

public enum AdminOutcome: Sendable {
    case done
    /// The user dismissed the password dialog.
    case cancelled
    case failed(String)
}

public enum Remover {
    /// With `askAdmin`, whatever macOS refuses for lack of permissions is retried
    /// once with administrator privileges: the system asks for the password.
    public static func remove(
        _ items: [ScanItem], mode: RemovalMode,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        askAdmin: Bool = false,
        runAsAdmin: (String) -> AdminOutcome = runWithAdminPrivileges
    ) -> RemovalResult {
        var result = removeAsUser(items, mode: mode, home: home)
        guard askAdmin else { return result }
        let denied = Set(result.failures.filter(\.needsAdmin).map(\.url))
        // Paths that cannot be quoted safely are never handed to a root shell.
        let retry = items.filter { denied.contains($0.url) && !$0.url.path.contains("\n") }
        guard !retry.isEmpty else { return result }

        let outcome = runAsAdmin(adminCommand(for: retry, mode: mode, home: home))
        for item in retry where !FileManager.default.fileExists(atPath: item.url.path) {
            result.failures.removeAll { $0.url == item.url }
            result.removed.append(item.url)
            result.bytes += item.size
        }
        let reason = switch outcome {
        case .done: "Non rimosso nemmeno con i privilegi di amministratore: macOS lo protegge."
        case .cancelled: "Servono i privilegi di amministratore, ma la richiesta è stata annullata."
        case .failed(let message): "Richiesta dei privilegi di amministratore non riuscita: \(message)"
        }
        for index in result.failures.indices where retry.contains(where: { $0.url == result.failures[index].url }) {
            result.failures[index] = .init(url: result.failures[index].url, reason: reason, needsAdmin: true)
        }
        return result
    }

    /// Shell command that removes `items` when run as root. Every path has
    /// already passed `SafetyGuard` in `removeAsUser`.
    static func adminCommand(for items: [ScanItem], mode: RemovalMode, home: URL) -> String {
        let trash = home.appendingPathComponent(".Trash").standardizedFileURL
        let stamp = Int(Date().timeIntervalSince1970)
        let commands = items.map { item -> String in
            let source = quote(item.url.path)
            if mode == .permanent || item.url.standardizedFileURL.path.hasPrefix(trash.path + "/") {
                return "/bin/rm -rf -- \(source)"
            }
            let name = item.url.lastPathComponent
            let ext = item.url.pathExtension
            let renamed = item.url.deletingPathExtension().lastPathComponent + " \(stamp)" + (ext.isEmpty ? "" : ".\(ext)")
            // Handed over to the user, so the Trash can be emptied without a password.
            return "d=\(quote(trash.appendingPathComponent(name).path)); "
                + "if [ -e \"$d\" ]; then d=\(quote(trash.appendingPathComponent(renamed).path)); fi; "
                + "/bin/mv -- \(source) \"$d\" && /usr/sbin/chown -R \(getuid()) \"$d\""
        }
        return commands.joined(separator: "; ") + "; true"
    }

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a shell command as root; macOS shows its own password dialog.
    public static func runWithAdminPrivileges(_ command: String) -> AdminOutcome {
        let literal = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(literal)\" with prompt "
            + "\"Sweep ha bisogno dei privilegi di amministratore per rimuovere gli elementi protetti.\" "
            + "with administrator privileges"
        // NSAppleScript is main-thread only.
        let run = { () -> AdminOutcome in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            guard let error else { return .done }
            if error[NSAppleScript.errorNumber] as? Int == -128 { return .cancelled }
            return .failed(error[NSAppleScript.errorMessage] as? String ?? "errore sconosciuto")
        }
        return Thread.isMainThread ? run() : DispatchQueue.main.sync(execute: run)
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain, [EPERM, EACCES].contains(Int32(error.code)) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isPermissionError) ?? false
    }

    private static func removeAsUser(_ items: [ScanItem], mode: RemovalMode, home: URL) -> RemovalResult {
        let fm = FileManager.default
        let trashPrefix = home.appendingPathComponent(".Trash").standardizedFileURL.path + "/"
        var result = RemovalResult(mode: mode)

        for item in items {
            guard SafetyGuard.canRemove(item.url, home: home) else {
                result.failures.append(.init(url: item.url, reason: "Percorso protetto: Sweep non lo elimina."))
                continue
            }
            // Things already in the Trash can only be deleted for good.
            let inTrash = item.url.standardizedFileURL.path.hasPrefix(trashPrefix)
            do {
                if mode == .permanent || inTrash {
                    try fm.removeItem(at: item.url)
                } else {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                }
                result.removed.append(item.url)
                result.bytes += item.size
            } catch {
                result.failures.append(.init(
                    url: item.url, reason: error.localizedDescription, needsAdmin: isPermissionError(error)))
            }
        }
        return result
    }
}
