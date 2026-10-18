import Foundation

public struct SelfControlEngine {
    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    public static func locate() -> SelfControlEngine? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("SelfControl.app/Contents/MacOS/selfcontrol-cli"))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/SelfControl.app/Contents/MacOS/selfcontrol-cli"))
        candidates.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/SelfControl.app/Contents/MacOS/selfcontrol-cli"))
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
            .map { SelfControlEngine(executable: $0) }
    }

    public static func validate(_ allowlist: Allowlist) throws {
        guard !allowlist.allowEducationDomains else { throw LockedInError.educationalWildcardUnsupported }
        guard !allowlist.domains.isEmpty else { throw LockedInError.emptyAllowlist }
    }

    public static func blocklistData(for allowlist: Allowlist) throws -> Data {
        try validate(allowlist)
        return try PropertyListSerialization.data(
            fromPropertyList: ["HostBlacklist": allowlist.domains, "BlockAsWhitelist": true],
            format: .binary, options: 0
        )
    }

    public static func startArguments(blocklist: URL, endDate: Date) -> [String] {
        let formatter = ISO8601DateFormatter()
        let settings: [String: Bool] = [
            "AllowLocalNetworks": true,
            "EvaluateCommonSubdomains": true,
            "IncludeLinkedDomains": true,
            "ClearCaches": false,
            "EnableErrorReporting": false,
            "BlockSoundShouldPlay": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: settings, options: .sortedKeys)
        return ["start", "--blocklist", blocklist.path, "--enddate", formatter.string(from: endDate),
                "--settings", String(decoding: data, as: UTF8.self)]
    }

    public static func parseRunningStatus(_ output: String) -> Bool? {
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines.reversed() {
            if line == "YES" || line.hasSuffix("] YES") { return true }
            if line == "NO" || line.hasSuffix("] NO") { return false }
        }
        return nil
    }

    public func isRunning() async throws -> Bool {
        let output = try await run(["is-running"], timeout: 10)
        guard let running = Self.parseRunningStatus(output) else { throw LockedInError.engineFailed }
        return running
    }

    public func start(allowlist: Allowlist, endDate: Date, directory: URL) async throws {
        try Self.validate(allowlist)
        guard endDate.timeIntervalSinceNow > 0, endDate.timeIntervalSinceNow <= 86_401 else {
            throw LockedInError.invalidDuration
        }
        if try await isRunning() { throw LockedInError.sessionAlreadyActive }
        let path = directory.appendingPathComponent("session-\(UUID().uuidString).selfcontrol")
        try Self.blocklistData(for: allowlist).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        defer { try? FileManager.default.removeItem(at: path) }
        _ = try await run(Self.startArguments(blocklist: path, endDate: endDate), timeout: 300)
        guard try await isRunning() else { throw LockedInError.engineFailed }
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        let executable = self.executable
        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            guard process.terminationStatus == 0 else { throw LockedInError.engineFailed }
            return String(decoding: output, as: UTF8.self)
        }.value
    }
}
