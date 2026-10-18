import XCTest
@testable import LockedInCore

final class LockedInCoreTests: XCTestCase {
    private let clock = SessionClock(now: Date(timeIntervalSince1970: 1_800_000_000), uptime: 1_000, bootID: "boot-a")

    func testDomainsRespectLabelBoundaries() throws {
        let list = try Allowlist(domains: [" Example.COM ", "example.com."], allowEducationDomains: false)
        XCTAssertEqual(list.domains, ["example.com"])
        XCTAssertTrue(list.allows(host: "sub.example.com"))
        XCTAssertFalse(list.allows(host: "notexample.com"))
        XCTAssertFalse(list.allows(host: "example.com.evil.test"))
    }

    func testAllEducationalDomainsWithoutLookalikes() throws {
        let list = try Allowlist(domains: [], allowEducationDomains: true)
        XCTAssertTrue(list.allows(host: "new-university.edu"))
        XCTAssertTrue(list.allows(host: "canvas.some.school.edu"))
        XCTAssertFalse(list.allows(host: "school.edu.evil.test"))
        XCTAssertFalse(list.allows(host: "fake-edu.com"))
        XCTAssertFalse(list.allows(host: "school.edu.cn"))
    }

    func testRejectsBroadOrMalformedRules() {
        for domain in ["*", "*.edu", "https://example.com", "example.com/private", "user@example.com", "example.com:443", "x..edu", "-x.com", "x.com?allow=all"] {
            XCTAssertThrowsError(try Allowlist(domains: [domain], allowEducationDomains: false), domain)
        }
        XCTAssertThrowsError(try Allowlist(domains: [], allowEducationDomains: false))
    }

    func testImportedProfilesAreValidated() throws {
        let invalid = Data(#"{"domains":["*"],"allowEducationDomains":false}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Allowlist.self, from: invalid))
    }

    func testClockChangesCannotShortenSameBootSession() throws {
        let session = try FocusSession(minutes: 60, allowlist: .starter, clock: clock)
        let jumped = SessionClock(now: clock.now.addingTimeInterval(86_400), uptime: 1_060, bootID: "boot-a")
        XCTAssertEqual(session.remainingSeconds(at: jumped), 3_540)
        let ended = SessionClock(now: clock.now, uptime: 4_600, bootID: "boot-a")
        XCTAssertFalse(session.isActive(at: ended))
    }

    func testSessionSurvivesRebootUsingRecordedDeadline() throws {
        let session = try FocusSession(minutes: 60, allowlist: .starter, clock: clock)
        let rebooted = SessionClock(now: clock.now.addingTimeInterval(1_200), uptime: 100, bootID: "boot-b")
        XCTAssertEqual(session.remainingSeconds(at: rebooted), 2_400)
    }

    func testActiveSessionCannotBeReplacedOrProfileChanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SessionStore(directory: directory)
        let started = try store.start(minutes: 60, allowlist: .starter, clock: clock)
        XCTAssertThrowsError(try store.start(minutes: 1, allowlist: .starter, clock: clock))
        XCTAssertThrowsError(try store.saveProfile(.starter, clock: clock))
        XCTAssertEqual(try store.session()?.id, started.id)
        let after = SessionClock(now: clock.now.addingTimeInterval(3_601), uptime: 4_601, bootID: "boot-a")
        XCTAssertNoThrow(try store.saveProfile(.starter, clock: after))
        XCTAssertNoThrow(try store.start(minutes: 25, allowlist: .starter, clock: after))
    }

    func testRejectsInvalidDuration() {
        for minutes in [0, -1, 1_441, Int.max] {
            XCTAssertThrowsError(try FocusSession(minutes: minutes, allowlist: .starter, clock: clock))
        }
    }

    func testEngineRejectsEducationalWildcardInsteadOfPretendingItWorks() throws {
        let list = try Allowlist(domains: ["example.edu"], allowEducationDomains: true)
        XCTAssertThrowsError(try SelfControlEngine.blocklistData(for: list))
    }

    func testEngineGeneratesActualUpstreamAllowlistFile() throws {
        let list = try Allowlist(domains: ["example.edu"], allowEducationDomains: false)
        let data = try SelfControlEngine.blocklistData(for: list)
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["BlockAsWhitelist"] as? Bool, true)
        XCTAssertEqual(plist["HostBlacklist"] as? [String], ["example.edu"])
    }

    func testCommandArgumentsDoNotInterpolateShellSyntax() throws {
        let file = URL(fileURLWithPath: "/tmp/focus 'quotes' $(literal)/allowlist.selfcontrol")
        let arguments = SelfControlEngine.startArguments(blocklist: file, endDate: clock.now)
        XCTAssertEqual(arguments[2], file.path)
        XCTAssertEqual(arguments[0], "start")
        XCTAssertFalse(arguments.contains("sudo"))
    }

    func testOnlyRecognizedEngineStatusIsAccepted() {
        XCTAssertEqual(SelfControlEngine.parseRunningStatus("2026-10-17 tool[12:34] YES\n"), true)
        XCTAssertEqual(SelfControlEngine.parseRunningStatus("2026-10-17 tool[12:34] NO\n"), false)
        XCTAssertNil(SelfControlEngine.parseRunningStatus("could not determine status"))
    }
}
