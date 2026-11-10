import CryptoKit
import Foundation

/// Why an update could not be checked for, downloaded or installed, in words a person can act on.
public enum UpdateError: Error, Equatable, Sendable {
    case network(String)
    case rateLimited
    /// GitHub answered, but not with something Island understands.
    case unreadable
    /// The latest release has no disk image to install.
    case noInstaller
    /// The release has no checksum file, so the download could not be checked.
    case noChecksum
    case checksumMismatch
    case badAddress(String)
    /// The app is somewhere it cannot replace itself (a disk image, a read-only folder, the Downloads folder before it was moved).
    case cannotReplaceHere(String)
    /// The download is not a usable Island (wrong app, not newer, wrong kind of Mac, damaged).
    case notAUsableUpdate(String)
    case installFailed(String)

    public var message: String {
        switch self {
        case .network(let detail): "Couldn't reach GitHub. \(detail)"
        case .rateLimited: "GitHub is asking for a short break. Try again in a few minutes."
        case .unreadable: "GitHub's answer wasn't something Island could read."
        case .noInstaller: "That release has no disk image to install."
        case .noChecksum: "That release has no checksum, so Island won't install it."
        case .checksumMismatch: "The download didn't match its checksum, so Island threw it away. Try again."
        case .badAddress(let address): "Island won't download from \(address)."
        case .cannotReplaceHere(let why): why
        case .notAUsableUpdate(let why): "The download can't be used: \(why)"
        case .installFailed(let why): "The update couldn't be installed: \(why)"
        }
    }
}

/// A published release of Island (GitHub's "latest release"), reduced to what updating needs.
public struct UpdateRelease: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    /// The release notes as published (they end with the install guide).
    public var notes: String
    public var pageURL: URL
    public var dmgName: String
    public var dmgURL: URL
    public var dmgSize: Int?
    public var checksumURL: URL?
    public var publishedAt: Date?

    public init(
        version: AppVersion, tag: String, notes: String, pageURL: URL, dmgName: String, dmgURL: URL, dmgSize: Int? = nil,
        checksumURL: URL? = nil, publishedAt: Date? = nil
    ) {
        self.version = version
        self.tag = tag
        self.notes = notes
        self.pageURL = pageURL
        self.dmgName = dmgName
        self.dmgURL = dmgURL
        self.dmgSize = dmgSize
        self.checksumURL = checksumURL
        self.publishedAt = publishedAt
    }

    /// What is new in this version: the notes up to the install guide, which an updating person does not need.
    public var whatsNew: String { UpdateNotes.whatsNew(from: notes) }
    /// The same, as plain text for Settings.
    public var whatsNewPlain: String { UpdateNotes.plainText(from: whatsNew) }
}

public enum UpdateNotes {
    /// Release notes as plain text for a small window: heading marks and list markers made readable, bold and code marks dropped.
    public static func plainText(from markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            lines.append(line)
        }
        // Not more than one blank line in a row, and none at either end.
        var collapsed: [String] = []
        for line in lines where !(line.isEmpty && collapsed.last?.isEmpty != false) { collapsed.append(line) }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The notes without their "Install" section (and anything after it).
    public static func whatsNew(from notes: String) -> String {
        var kept: [Substring] = []
        for line in notes.split(separator: "\n", omittingEmptySubsequences: false) {
            let heading = line.trimmingCharacters(in: .whitespaces).lowercased()
            if heading.hasPrefix("#"), heading.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) == "install" { break }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum UpdateDecoding {
    private struct WireAsset: Decodable {
        var name: String?
        var browserDownloadUrl: String?
        var size: Int?
        enum CodingKeys: String, CodingKey { case name, browserDownloadUrl = "browser_download_url", size }
    }

    private struct WireRelease: Decodable {
        var tagName: String?
        var body: String?
        var htmlUrl: String?
        var draft: Bool?
        var prerelease: Bool?
        var publishedAt: String?
        var assets: [WireAsset]?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", body, htmlUrl = "html_url", draft, prerelease, publishedAt = "published_at", assets
        }
    }

    /// GitHub's answer for a release. A draft, a pre-release or a tag that is not a version is no release for this purpose.
    public static func release(from data: Data) throws -> UpdateRelease {
        guard let wire = try? JSONDecoder().decode(WireRelease.self, from: data),
              let tag = wire.tagName, let version = AppVersion(tag), wire.draft != true, wire.prerelease != true,
              let page = wire.htmlUrl.flatMap(URL.init(string:))
        else { throw UpdateError.unreadable }

        let assets = (wire.assets ?? []).compactMap { asset -> (name: String, url: URL, size: Int?)? in
            guard let name = asset.name, let url = asset.browserDownloadUrl.flatMap(URL.init(string:)) else { return nil }
            return (name, url, asset.size)
        }
        // The disk image: Island's own (named Island-<version>.dmg) before any other.
        let dmg = assets.first { $0.name.hasPrefix("Island") && $0.name.hasSuffix(".dmg") } ?? assets.first { $0.name.hasSuffix(".dmg") }
        guard let dmg else { throw UpdateError.noInstaller }
        let checksum = assets.first { $0.name == dmg.name + ".sha256" }

        let formatter = ISO8601DateFormatter()
        return UpdateRelease(
            version: version, tag: tag, notes: wire.body ?? "", pageURL: page, dmgName: dmg.name, dmgURL: dmg.url, dmgSize: dmg.size,
            checksumURL: checksum?.url, publishedAt: wire.publishedAt.flatMap(formatter.date(from:)))
    }
}

/// `shasum -a 256` writes "<64 hex digits>  <file name>"; this reads the digits.
public enum ChecksumFile {
    public static func parse(_ text: String) -> String? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let hash = first.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }
}

public enum FileChecksum {
    /// The SHA-256 of a file as lowercase hex, read in pieces so a large file never sits in memory.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
