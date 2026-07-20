import Foundation
import os

public nonisolated struct Storage {
    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public static func production() -> Storage {
        let applicationSupportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return Storage(
            baseDirectory: applicationSupportDirectory
                .appendingPathComponent("Bopop", isDirectory: true)
        )
    }

    public var scriptsDirectory: URL {
        baseDirectory.appendingPathComponent("Scripts", isDirectory: true)
    }

    public var usageFileURL: URL {
        baseDirectory.appendingPathComponent("usage.json")
    }

    public var clipboardFileURL: URL {
        baseDirectory.appendingPathComponent("clipboard.json")
    }

    public var scriptsLogURL: URL {
        baseDirectory.appendingPathComponent("scripts.log")
    }

    public var ratesFileURL: URL {
        baseDirectory.appendingPathComponent("rates.json")
    }

    public func ensureDirectories() throws {
        let fileManager = FileManager.default
        let directoryAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]

        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )
        try fileManager.createDirectory(
            at: scriptsDirectory,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )
        try fileManager.setAttributes(
            directoryAttributes,
            ofItemAtPath: baseDirectory.path
        )
        try fileManager.setAttributes(
            directoryAttributes,
            ofItemAtPath: scriptsDirectory.path
        )
    }

    public func save<T: Codable>(_ value: T, version: Int, to url: URL) throws {
        let envelope = Envelope(version: version, payload: value)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public func load<T: Codable>(
        _ type: T.Type,
        expectedVersion: Int,
        from url: URL
    ) -> T? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
            guard envelope.version == expectedVersion else {
                quarantine(url, using: fileManager)
                return nil
            }
            return envelope.payload
        } catch {
            quarantine(url, using: fileManager)
            return nil
        }
    }

    public func appendScriptLog(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(timestamp) \(line)\n"
        guard let data = entry.data(using: .utf8) else {
            return
        }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: scriptsLogURL.path) {
                let handle = try FileHandle(forWritingTo: scriptsLogURL)
                defer { try? handle.close() }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: scriptsLogURL, options: .atomic)
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: scriptsLogURL.path
            )
        } catch {
            Self.logger.error(
                "Could not append script log at \(self.scriptsLogURL.path, privacy: .private)"
            )
        }
    }

    private static let logger = Logger(
        subsystem: "com.oneone.bopop",
        category: "storage"
    )

    private func quarantine(_ url: URL, using fileManager: FileManager) {
        let corruptURL = URL(fileURLWithPath: url.path + ".corrupt")
        if fileManager.fileExists(atPath: corruptURL.path) {
            try? fileManager.removeItem(at: corruptURL)
        }
        try? fileManager.moveItem(at: url, to: corruptURL)
        Self.logger.error(
            "Rejected storage file at \(url.path, privacy: .private); quarantine path: \(corruptURL.path, privacy: .private)"
        )
    }

    private struct Envelope<Payload: Codable>: Codable {
        let version: Int
        let payload: Payload
    }
}
