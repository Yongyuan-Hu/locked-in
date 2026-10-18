import AppKit
import Foundation
import LockedInCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var section = "Focus"
    @Published var minutes = 60
    @Published var domainText = ""
    @Published var session: FocusSession?
    @Published var remainingSeconds = 0
    @Published var engineRunning = false
    @Published var engineChecked = false
    @Published var isStarting = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var engineMessage = "Checking the blocking engine…"
    private var store: SessionStore?
    private var refreshing = false
    private var engine: SelfControlEngine? { SelfControlEngine.locate() }

    init() {
        do {
            let store = try SessionStore()
            self.store = store
            let list = try store.profile()
            domainText = list.domains.joined(separator: "\n")
            session = try store.session()
            remainingSeconds = session?.remainingSeconds() ?? 0
        } catch { errorMessage = error.localizedDescription }
    }

    var isActive: Bool { engineRunning || isStarting }
    var isOwnSession: Bool { engineRunning && remainingSeconds > 0 }
    var canStart: Bool { engine != nil && engineChecked && !isActive }
    var engineAvailable: Bool { engine != nil }
    var timerText: String { String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60) }
    var domainCount: Int { (try? currentAllowlist().domains.count) ?? 0 }

    func refresh() async {
        guard !refreshing, !isStarting else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            session = try store?.session()
            remainingSeconds = session?.remainingSeconds() ?? 0
            guard let engine else {
                engineChecked = false
                engineMessage = "Blocking engine not installed"
                return
            }
            engineRunning = try await engine.isRunning()
            engineChecked = true
            engineMessage = engineRunning ? "Systemwide block active" : "SelfControl engine ready"
        } catch {
            engineChecked = false
            engineMessage = "Unable to verify blocking status"
        }
    }

    func currentAllowlist() throws -> Allowlist {
        let lines = domainText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return try Allowlist(domains: lines, allowEducationDomains: false)
    }

    func saveAllowlist() {
        do {
            guard !isActive, let store else { return }
            let list = try currentAllowlist()
            try store.saveProfile(list)
            domainText = list.domains.joined(separator: "\n")
            notice = "Your allowlist is saved on this Mac."
        } catch { errorMessage = error.localizedDescription }
    }

    func start() async {
        await refresh()
        guard canStart, let engine, let store else {
            errorMessage = "The engine is not ready, or another SelfControl block is already running."
            return
        }
        do {
            let list = try currentAllowlist()
            try SelfControlEngine.validate(list)
            let alert = NSAlert()
            alert.messageText = "Start a \(minutes)-minute systemwide block?"
            alert.informativeText = "Internet access will be restricted to the addresses resolved for your allowlist. The block cannot be cancelled early, even by quitting this app or restarting your Mac. Check that you have included the websites and sign-in services you need. macOS may ask you to authorize SelfControl's blocking engine."
            alert.addButton(withTitle: "Start session")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try store.saveProfile(list)
            let clock = SessionClock.current
            let deadline = clock.now.addingTimeInterval(Double(minutes) * 60)
            isStarting = true
            engineMessage = "Waiting for engine authorization and confirmation…"
            do {
                try await engine.start(allowlist: list, endDate: deadline, directory: store.directory)
                _ = try store.start(minutes: minutes, allowlist: list, clock: clock)
                notice = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isStarting = false
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func importAllowlist() {
        guard !isActive else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Import a LockedIn allowlist. Your file stays on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let list = try JSONDecoder().decode(Allowlist.self, from: Data(contentsOf: url))
            try SelfControlEngine.validate(list)
            try store?.saveProfile(list)
            domainText = list.domains.joined(separator: "\n")
            notice = "Allowlist imported."
        } catch { errorMessage = error.localizedDescription }
    }

    func exportAllowlist() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "locked-in-allowlist.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(currentAllowlist()).write(to: url, options: .atomic)
            notice = "Allowlist exported."
        } catch { errorMessage = error.localizedDescription }
    }

    func openEngine() {
        guard let engine else { return }
        let app = engine.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open(app)
    }
}
