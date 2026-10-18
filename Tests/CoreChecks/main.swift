import Foundation
import LockedInCore

enum CheckError: Error { case failed(String) }
func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
    guard condition() else { throw CheckError.failed(description) }
    print("PASS \(description)")
}
func rejects(_ description: String, _ action: () throws -> Void) throws {
    do { try action() } catch { print("PASS \(description)"); return }
    throw CheckError.failed(description)
}

do {
    let list = try Allowlist(domains: [" EXAMPLE.edu ", "example.edu."], allowEducationDomains: false)
    try check(list.domains == ["example.edu"], "normalization and deduplication")
    try check(list.allows(host: "canvas.example.edu"), "listed school's subdomain")
    try check(!list.allows(host: "example.edu.evil.test"), "suffix lookalike is rejected")
    try check(!list.allows(host: "notexample.edu"), "label boundary is enforced")
    for input in ["*", "*.edu", "https://example.edu", "example.edu/private", "user@example.edu", "example.edu:443", "x..edu"] {
        try rejects("invalid rule: \(input)") { _ = try Allowlist(domains: [input], allowEducationDomains: false) }
    }
    let educational = try Allowlist(domains: ["example.edu"], allowEducationDomains: true)
    try rejects("unsupported wildcard cannot reach the firewall") { _ = try SelfControlEngine.blocklistData(for: educational) }
    let data = try SelfControlEngine.blocklistData(for: list)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    try check(plist["BlockAsWhitelist"] as? Bool == true, "engine file is explicitly an allowlist")
    try check(plist["HostBlacklist"] as? [String] == ["example.edu"], "engine file contains the selected hostnames")
    try check(SelfControlEngine.parseRunningStatus("2026 tool[1:2] YES\n") == true, "engine active status")
    try check(SelfControlEngine.parseRunningStatus("2026 tool[1:2] NO\n") == false, "engine idle status")
    try check(SelfControlEngine.parseRunningStatus("ERROR") == nil, "unknown status never means idle")
    let clock = SessionClock(now: Date(), uptime: 1_000, bootID: "test-boot")
    let session = try FocusSession(minutes: 60, allowlist: list, clock: clock)
    let adjusted = SessionClock(now: clock.now.addingTimeInterval(86_400), uptime: 1_060, bootID: "test-boot")
    try check(session.remainingSeconds(at: adjusted) == 3_540, "same-boot clock changes do not shorten the display timer")
    let ended = SessionClock(now: clock.now.addingTimeInterval(3_600), uptime: 4_600, bootID: "test-boot")
    try check(!session.isActive(at: ended), "timer expires at the deadline")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    _ = try store.start(minutes: 60, allowlist: list, clock: clock)
    try rejects("active sessions cannot be replaced") { _ = try store.start(minutes: 1, allowlist: list, clock: clock) }
    try rejects("active allowlists cannot be edited") { try store.saveProfile(list, clock: clock) }
    let file = URL(fileURLWithPath: "/tmp/quotes ' and $(literal)/list.selfcontrol")
    try check(SelfControlEngine.startArguments(blocklist: file, endDate: clock.now)[2] == file.path, "paths remain literal process arguments")
    print("All core checks passed. No firewall settings were changed.")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
