import AppKit
import SwiftUI
import LockedInCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.applicationIconImage = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "LockedIn")
    }
}

@main
struct LockedInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("LockedIn", id: "main") {
            MainView(model: model)
                .frame(minWidth: 840, minHeight: 620)
        }
        .defaultSize(width: 960, height: 700)
        MenuBarExtra("LockedIn", systemImage: "lock.shield") {
            Text(model.isOwnSession ? "Focus session · \(model.timerText) left" : (model.isActive ? model.engineMessage : "Ready when you are"))
            Button("Open LockedIn") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit LockedIn") { NSApplication.shared.terminate(nil) }
        }
    }
}

private struct MainView: View {
    @ObservedObject var model: AppModel
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.blue)
                    Text("LockedIn").font(.title2.weight(.semibold))
                }
                VStack(spacing: 6) {
                    navigation("Focus", icon: "timer")
                    navigation("Allowlist", icon: "checklist")
                    navigation("Engine", icon: "network")
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.engineChecked ? "Engine connected" : "Engine unavailable", systemImage: model.engineChecked ? "checkmark.circle" : "circle.dashed")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Version \(AppConstants.version)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(24).frame(width: 180).background(.quaternary.opacity(0.35))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch model.section {
                    case "Allowlist": allowlist
                    case "Engine": setup
                    default: focus
                    }
                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(36).frame(maxWidth: 760, alignment: .leading)
            }.frame(maxWidth: .infinity)
        }
        .onReceive(clock) { _ in Task { await model.refresh() } }
        .task { await model.refresh() }
        .alert("LockedIn", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func navigation(_ name: String, icon: String) -> some View {
        Button { model.section = name } label: {
            Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(model.section == name ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(model.isActive ? "Stay with what matters." : "Make room for your work.")
                .font(.largeTitle.weight(.semibold))
            Text("Only the websites you choose. One session at a time.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(model.isActive ? "FOCUS SESSION" : "YOUR NEXT SESSION", systemImage: "timer")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if model.isActive {
                        Label(model.engineMessage, systemImage: model.engineRunning ? "checkmark.shield" : "hourglass")
                            .font(.caption).foregroundStyle(model.engineRunning ? .green : .orange)
                    }
                }
                if model.isActive {
                    Text(model.isOwnSession ? model.timerText : (model.isStarting ? "Starting…" : "Locked in")).font(.system(size: model.isOwnSession ? 64 : 42, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(model.isOwnSession ? "Time remaining" : model.engineMessage).foregroundStyle(.secondary)
                    Text(model.isOwnSession ? "Your allowlist is locked until this session ends. Closing this app does not end the session." : (model.isStarting ? "Complete the engine’s macOS authorization prompt. Blocking status will appear after confirmation." : "An existing SelfControl block is running. New blocks are disabled until it finishes."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(model.minutes)").font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("minutes").font(.title3).foregroundStyle(.secondary)
                    }
                    Picker("Session length", selection: $model.minutes) {
                        ForEach([5, 25, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                    }.pickerStyle(.segmented)
                    Button("Start \(model.minutes)-minute session") { Task { await model.start() } }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart)
                }
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 24) {
                Label("\(model.domainCount) saved profile domains", systemImage: "checklist")
                Label("Systemwide on this Mac", systemImage: "desktopcomputer")
            }.font(.callout).foregroundStyle(.secondary)
            if !model.engineChecked {
                Button("Check the blocking engine") { model.section = "Engine" }.buttonStyle(.link)
            }
            Divider()
            Text("Powered by SelfControl’s systemwide firewall. VPNs, shared hosting, and changing server addresses can affect blocking. A short test is recommended before a long session.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var allowlist: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your useful corner of the web.").font(.largeTitle.weight(.semibold))
            Text("Enter one hostname per line. SelfControl evaluates common subdomains and supporting services. Your list stays on this Mac.").foregroundStyle(.secondary)
            Label("School websites need explicit hostnames. Blanket .edu rules are not supported by this engine.", systemImage: "graduationcap").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $model.domainText).font(.system(.body, design: .monospaced))
                .padding(10).frame(minHeight: 280)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                .disabled(model.isActive)
            HStack {
                Button("Save allowlist", action: model.saveAllowlist).buttonStyle(.borderedProminent).disabled(model.isActive)
                Button("Import…", action: model.importAllowlist).disabled(model.isActive)
                Button("Export…", action: model.exportAllowlist)
                Spacer()
                Text("\(model.domainCount) domains").font(.caption).foregroundStyle(.secondary)
            }
            if model.isActive { Label("Editing unlocks when your session ends.", systemImage: "lock").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("The same blocking foundation.").font(.largeTitle.weight(.semibold))
            Text("LockedIn uses the unmodified SelfControl 4.0.2 engine to restrict network access across your Mac. No browser extension is required.").foregroundStyle(.secondary)
            Label(model.engineMessage, systemImage: model.engineChecked ? "checkmark.shield" : "exclamationmark.circle").font(.headline)
            Button("Check engine") { Task { await model.refresh() } }
            if model.engineAvailable { Button("Open SelfControl engine", action: model.openEngine) }
            Divider()
            Text("A session cannot be cancelled early. The engine’s privileged helper maintains the block after LockedIn quits or the Mac restarts. macOS asks for authorization when needed.").font(.callout)
            Text("Website addresses resolve to servers. Allowing one server may also allow another website using it. The engine also allows Google IP ranges when Google services are listed. A strict domain-by-domain guarantee is not available with this engine.").font(.callout).foregroundStyle(.secondary)
            Text("Automatic access to every .edu site is not supported. Add the educational hostnames you need before starting a session.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Credits: SelfControl by Charlie Stigler, Steve Lambert, and contributors. Engine and source are distributed under GPL-3.0-or-later. The build includes its corresponding source.").font(.caption).foregroundStyle(.secondary)
            Text("LockedIn adds no analytics or cloud accounts. Its start command disables the engine’s optional error reporting for that session. Other independently configured SelfControl settings remain under SelfControl’s control.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func setupStep<Content: View>(_ number: String, _ title: String, _ detail: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.headline).frame(width: 30, height: 30).background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                action()
            }
        }
    }
}
