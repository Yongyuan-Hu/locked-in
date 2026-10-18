import Foundation
import Darwin

public struct SessionClock {
    public let now: Date
    public let uptime: TimeInterval
    public let bootID: String

    public init(now: Date, uptime: TimeInterval, bootID: String) {
        self.now = now
        self.uptime = uptime
        self.bootID = bootID
    }

    public static var current: SessionClock {
        var size = 0
        _ = sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        let success = sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0
        let bootID = success ? String(cString: bytes) : "unavailable"
        return SessionClock(now: Date(), uptime: ProcessInfo.processInfo.systemUptime, bootID: bootID)
    }
}

public struct FocusSession: Codable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let endsAt: Date
    public let durationMinutes: Int
    public let startedUptime: TimeInterval
    public let bootID: String
    public let allowlist: Allowlist

    public init(minutes: Int, allowlist: Allowlist, clock: SessionClock = .current) throws {
        guard (1...1_440).contains(minutes) else { throw LockedInError.invalidDuration }
        self.id = UUID()
        self.startedAt = clock.now
        self.endsAt = clock.now.addingTimeInterval(Double(minutes) * 60)
        self.durationMinutes = minutes
        self.startedUptime = clock.uptime
        self.bootID = clock.bootID
        self.allowlist = allowlist
    }

    public func remainingSeconds(at clock: SessionClock = .current) -> Int {
        let remaining: TimeInterval
        if bootID != "unavailable" && clock.bootID == bootID && clock.uptime >= startedUptime {
            remaining = Double(durationMinutes) * 60 - (clock.uptime - startedUptime)
        } else {
            remaining = endsAt.timeIntervalSince(clock.now)
        }
        return max(0, min(durationMinutes * 60, Int(ceil(remaining))))
    }

    public func isActive(at clock: SessionClock = .current) -> Bool { remainingSeconds(at: clock) > 0 }
}

