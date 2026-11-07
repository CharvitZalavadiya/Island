import Foundation

public enum ArchiveError: Error, Equatable {
    case failed(String)
}

/// Zips and unzips with macOS's own `ditto`, so names with spaces and accents, and Mac metadata, survive.
/// Results go next to the original and never overwrite anything.
public enum ArchiveService {
    private static let ditto = "/usr/bin/ditto"

    /// `Folder` becomes `Folder.zip`; `report.txt` becomes `report.txt.zip`.
    public static func zip(_ source: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ArchiveError.failed("\(source.lastPathComponent) no longer exists.")
        }
        let output = OutputNamer.uniqueURL(for: URL(fileURLWithPath: source.path + ".zip"))
        // `--keepParent` puts a folder's own name at the top of the archive. For a single file it would instead put
        // the folder the file lives in there, which is not what Finder does, so it is used for folders only.
        var arguments = ["-c", "-k", "--sequesterRsrc"]
        if isDirectory.boolValue { arguments.append("--keepParent") }
        let result = try run(arguments + [source.path, output.path])
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw ArchiveError.failed(message(from: result, fallback: "Could not zip \(source.lastPathComponent)."))
        }
        return output
    }

    /// Several items become one `Archive.zip` next to the first of them, with every item at the archive's root.
    /// The items are copied (APFS makes that nearly free) into a hidden staging folder first, because `ditto` can only
    /// archive one thing; the staging folder is always removed again. Same-named items from different folders are
    /// numbered, and the originals are never touched.
    public static func zip(urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw ArchiveError.failed("There is nothing to zip.") }
        let fileManager = FileManager.default
        for url in urls where !fileManager.fileExists(atPath: url.path) {
            throw ArchiveError.failed("\(url.lastPathComponent) no longer exists.")
        }

        let parent = first.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".island-zip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        for url in urls {
            let copy = OutputNamer.uniqueURL(for: staging.appendingPathComponent(url.lastPathComponent))
            try fileManager.copyItem(at: url, to: copy)
        }

        let output = OutputNamer.uniqueURL(for: parent.appendingPathComponent("Archive.zip"))
        let result = try run(["-c", "-k", "--sequesterRsrc", staging.path, output.path])
        guard result.status == 0 else {
            try? fileManager.removeItem(at: output)
            throw ArchiveError.failed(message(from: result, fallback: "Could not zip these files."))
        }
        return output
    }

    /// Extracts next to the archive. An archive with a single item at its root gives that item (no extra folder);
    /// otherwise the contents go into a new folder named after the archive.
    public static func unzip(_ archive: URL) throws -> URL {
        let parent = archive.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".island-unzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }

        let result = try run(["-x", "-k", archive.path, staging.path])
        guard result.status == 0 else {
            throw ArchiveError.failed(message(from: result, fallback: "Could not unzip \(archive.lastPathComponent)."))
        }

        let items = try FileManager.default
            .contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "__MACOSX" }
        if items.count == 1 {
            let destination = OutputNamer.uniqueURL(for: parent.appendingPathComponent(items[0].lastPathComponent))
            try FileManager.default.moveItem(at: items[0], to: destination)
            return destination
        }
        let name = archive.deletingPathExtension().lastPathComponent
        let destination = OutputNamer.uniqueURL(for: parent.appendingPathComponent(name, isDirectory: true))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        for item in items {
            try FileManager.default.moveItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
        return destination
    }

    private static func run(_ arguments: [String]) throws -> CommandResult {
        try ProcessCommandRunner().run(ditto, arguments)
    }

    private static func message(from result: CommandResult, fallback: String) -> String {
        let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }
}
