import Foundation

public enum LockedInError: LocalizedError, Equatable {
    case invalidDomain(String)
    case emptyAllowlist
    case invalidDuration
    case sessionAlreadyActive
    case profileLocked
    case tooManyDomains
    case educationalWildcardUnsupported
    case engineUnavailable
    case engineFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let value): return "Enter a hostname such as example.com, without a path, port, or wildcard: \(value)"
        case .emptyAllowlist: return "Allow at least one website or enable educational websites."
        case .invalidDuration: return "Choose a session between 1 and 1,440 minutes."
        case .sessionAlreadyActive: return "A focus session is already running. It cannot be replaced or shortened."
        case .profileLocked: return "Your allowlist is locked until the current session ends."
        case .tooManyDomains: return "An allowlist can contain up to 1,000 hostnames."
        case .educationalWildcardUnsupported: return "SelfControl's systemwide firewall cannot automatically allow every .edu website. Add the school hostnames you need to the allowlist."
        case .engineUnavailable: return "The SelfControl engine could not be found. Use the bundled release app, or install SelfControl from selfcontrolapp.com."
        case .engineFailed: return "The SelfControl engine could not confirm the requested operation. Check SelfControl before trying again."
        }
    }
}

public struct Allowlist: Codable, Equatable {
    public let domains: [String]
    public let allowEducationDomains: Bool

    public init(domains: [String], allowEducationDomains: Bool) throws {
        let normalized = try domains.map(Self.normalizeDomain)
        self.domains = Array(Set(normalized)).sorted()
        self.allowEducationDomains = allowEducationDomains
        guard !self.domains.isEmpty || allowEducationDomains else { throw LockedInError.emptyAllowlist }
        guard self.domains.count <= 1_000 else { throw LockedInError.tooManyDomains }
    }

    public static func normalizeDomain(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty, value.utf8.count <= 253,
              value.unicodeScalars.allSatisfy({ $0.isASCII }),
              !value.contains(where: { "/:@?#*\\%".contains($0) }) else {
            throw LockedInError.invalidDomain(input)
        }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { throw LockedInError.invalidDomain(input) }
        return value
    }

    public func allows(host input: String) -> Bool {
        guard let host = try? Self.normalizeDomain(input) else { return false }
        if allowEducationDomains && host.hasSuffix(".edu") { return true }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static let starter = try! Allowlist(
        domains: ["chatgpt.com", "claude.ai", "coursera.org", "docs.google.com", "drive.google.com", "github.com", "wikipedia.org"],
        allowEducationDomains: false
    )

    private enum CodingKeys: String, CodingKey { case domains, allowEducationDomains }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            domains: container.decode([String].self, forKey: .domains),
            allowEducationDomains: container.decode(Bool.self, forKey: .allowEducationDomains)
        )
    }
}
