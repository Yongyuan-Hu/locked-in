import Foundation

public final class SessionStore {
    public let directory: URL
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    public init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LockedIn", isDirectory: true)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func save<T: Encodable>(_ value: T, name: String) throws {
        let url = directory.appendingPathComponent(name)
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func session() throws -> FocusSession? { try load(FocusSession.self, name: "session.json") }
    public func profile() throws -> Allowlist { try load(Allowlist.self, name: "allowlist.json") ?? .starter }

    public func saveProfile(_ profile: Allowlist, clock: SessionClock = .current) throws {
        if try session()?.isActive(at: clock) == true { throw LockedInError.profileLocked }
        try save(profile, name: "allowlist.json")
    }

    @discardableResult
    public func start(minutes: Int, allowlist: Allowlist, clock: SessionClock = .current) throws -> FocusSession {
        if try session()?.isActive(at: clock) == true { throw LockedInError.sessionAlreadyActive }
        let session = try FocusSession(minutes: minutes, allowlist: allowlist, clock: clock)
        try save(session, name: "session.json")
        return session
    }

}
