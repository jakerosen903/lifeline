import Foundation
import LifelineKit

/// "Your copy": export everything to one file, restore from one at the next launch (M6).
@MainActor
@Observable
final class BackupViewModel {
    private(set) var progressText: String?
    /// The file to hand to the share sheet once export is done.
    var shareURL: URL?
    private(set) var lastExport: (at: Date, bytes: Int64)?
    /// The copy the person picked, waiting on "Replace everything…?".
    var confirming: (url: URL, manifest: BackupManifest)?
    private(set) var relaunchText: String?
    private(set) var error: String?
    private let deps: Dependencies
    private let isSessionLive: () -> Bool
    private static let lastExportKey = "lastExport"

    init(deps: Dependencies, isSessionLive: @escaping () -> Bool) {
        self.deps = deps
        self.isSessionLive = isSessionLive
        if let at = UserDefaults.standard.object(forKey: Self.lastExportKey) as? Date {
            lastExport = (at, Int64(UserDefaults.standard.integer(forKey: Self.lastExportKey + ".bytes")))
        }
    }

    var lastExportText: String? {
        guard let lastExport else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: lastExport.bytes, countStyle: .file)
        return "Last copy: \(lastExport.at.formatted(.relative(presentation: .named))), \(size)"
    }

    var summaryText: String? {
        guard let m = confirming?.manifest else { return nil }
        let recordings = m.sessions == 1 ? "1 recording" : "\(m.sessions) recordings"
        let memories = m.memories == 1 ? "1 memory" : "\(m.memories) memories"
        return "\(recordings), \(memories), from \(m.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    static let liveSessionText = "Finish your recording first"

    /// Builds the file off the main actor; the share sheet opens when it is ready.
    func export() {
        guard !isSessionLive() else { error = Self.liveSessionText; return }
        error = nil
        progressText = "Copying your memories…"
        let root = deps.audioRoot, database = deps.database
        let folder = deps.exportWithoutShareSheet ? ((try? Backup.safetyCopyDirectory()) ?? FileManager.default.temporaryDirectory) : FileManager.default.temporaryDirectory
        let destination = folder.appending(path: Backup.defaultFileName())
        let share = !deps.exportWithoutShareSheet
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let manifest = try Backup.export(root: root, appVersion: Dependencies.appVersion, to: destination, database: database) { line in
                    Task { @MainActor in self?.progressText = line }
                }
                let bytes = Int64((try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0)
                await MainActor.run { self?.exported(destination, manifest: manifest, bytes: bytes, share: share) }
            } catch {
                await MainActor.run { self?.progressText = nil; self?.error = "Could not make a copy: \(error.localizedDescription)" }
            }
        }
    }

    private func exported(_ url: URL, manifest: BackupManifest, bytes: Int64, share: Bool) {
        progressText = nil
        lastExport = (.now, bytes)
        UserDefaults.standard.set(Date.now, forKey: Self.lastExportKey)
        UserDefaults.standard.set(Int(bytes), forKey: Self.lastExportKey + ".bytes")
        if share { shareURL = url; sharedFile = url }
    }

    /// The file handed to the share sheet; removed when the sheet closes.
    private var sharedFile: URL?

    /// The share sheet closed: the file in the temporary folder is a full copy of everything,
    /// and whatever the person did with it is done, so it goes now.
    func shareClosed() {
        guard let url = sharedFile else { return }
        sharedFile = nil
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }
    }

    /// The person picked a file (or the test named one): copy it and read what is inside off
    /// the main actor (an archive can hold hours of audio), then ask.
    func chose(_ url: URL) {
        guard !isSessionLive() else { error = Self.liveSessionText; return }
        progressText = "Reading the copy…"
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let local = FileManager.default.temporaryDirectory.appending(path: "restore-\(UUID().uuidString).lifeline")
                try? FileManager.default.removeItem(at: local)
                try FileManager.default.copyItem(at: url, to: local)
                let manifest = try Backup.inspect(local)
                await MainActor.run { self?.progressText = nil; self?.confirming = (local, manifest); self?.error = nil }
            } catch {
                await MainActor.run { self?.progressText = nil; self?.error = "That is not a Lifeline copy: \(error.localizedDescription)" }
            }
        }
    }

    /// Under `-uiTesting-restoreFrom`, Restore skips the picker.
    var testRestorePath: String? { deps.restoreFromPath }

    /// Unpacks and writes the safety copy off the main actor; the screen says what is happening.
    func confirmRestore() {
        guard let confirming else { return }
        self.confirming = nil
        progressText = "Saving a copy of what is on the phone…"
        let root = deps.audioRoot, database = deps.database
        Task.detached(priority: .userInitiated) { [weak self] in
            defer { try? FileManager.default.removeItem(at: confirming.url) }
            do {
                _ = try Backup.stage(confirming.url, root: root, appVersion: Dependencies.appVersion, database: database)
                await MainActor.run {
                    self?.progressText = nil
                    self?.relaunchText = "Your copy is ready. Close Lifeline and open it again to finish."
                    self?.error = nil
                }
            } catch Backup.Error.newerSchema {
                await MainActor.run { self?.progressText = nil; self?.error = "This copy was made by a newer version of Lifeline." }
            } catch {
                await MainActor.run { self?.progressText = nil; self?.error = "Could not restore: \(error.localizedDescription)" }
            }
        }
    }

    func cancelRestore() {
        if let url = confirming?.url { try? FileManager.default.removeItem(at: url) }
        confirming = nil
    }
}
