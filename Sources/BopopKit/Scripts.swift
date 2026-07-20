import Foundation

public nonisolated struct ScriptInfo: Equatable, Sendable {
    public let name: String
    public let path: String
}

// Holds only an immutable directory URL and performs a stateless synchronous
// scan per call (no cache to race on) — safe to run entirely off the main
// actor, which is the whole point: ScriptsProvider's directory scan must not
// block every other provider while it walks the filesystem.
public nonisolated final class ScriptCatalog: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func scripts() -> [ScriptInfo] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isDirectory != true,
                  fileManager.isExecutableFile(atPath: url.path)
            else {
                return nil
            }
            let configuredURL = directory.appendingPathComponent(url.lastPathComponent)
            return ScriptInfo(
                name: url.deletingPathExtension().lastPathComponent,
                path: configuredURL.path
            )
        }.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

public nonisolated struct ScriptRunResult: Sendable {
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let launchFailure: LaunchFailure?

    public nonisolated enum LaunchFailure: Equatable, Sendable {
        case missingShebang
        case failed(String)
    }
}

public enum ScriptRunner {
    private nonisolated static let outputLimit = 65_536

    public static nonisolated func run(
        scriptAt path: String,
        workingDirectory: URL
    ) async -> ScriptRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let termination = ScriptTermination()
        process.terminationHandler = { @Sendable process in
            let status = process.terminationStatus
            Task {
                await termination.finish(with: status)
            }
        }

        do {
            try process.run()
        } catch {
            let failure: ScriptRunResult.LaunchFailure = isMissingShebang(error)
                ? .missingShebang
                : .failed(error.localizedDescription)
            return ScriptRunResult(
                exitCode: nil,
                stdout: "",
                stderr: "",
                launchFailure: failure
            )
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        async let stdoutData = drain(stdoutHandle)
        async let stderrData = drain(stderrHandle)
        async let terminationStatus = termination.wait()

        let (capturedStdout, capturedStderr) = await (stdoutData, stderrData)
        let exitCode = await terminationStatus
        return ScriptRunResult(
            exitCode: exitCode,
            stdout: String(decoding: capturedStdout, as: UTF8.self),
            stderr: String(decoding: capturedStderr, as: UTF8.self),
            launchFailure: nil
        )
    }

    private static nonisolated func isMissingShebang(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain, error.code == 8 {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isMissingShebang(underlying)
        }
        return false
    }

    private static nonisolated func drain(_ fileHandle: FileHandle) async -> Data {
        // On macOS 15.7, AsyncBytes did not yield live pipe data before EOF.
        let capture = ScriptPipeCapture(limit: outputLimit)
        return await withCheckedContinuation { continuation in
            capture.setContinuation(continuation)
            fileHandle.readabilityHandler = { @Sendable handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    capture.finish()
                } else {
                    capture.append(chunk)
                }
            }
        }
    }
}

public final class ScriptsProvider: ResultProvider {
    public let id: ProviderID = .scripts

    private let catalog: ScriptCatalog

    public init(catalog: ScriptCatalog) {
        self.catalog = catalog
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general, !query.term.isEmpty else {
            return []
        }

        return catalog.scripts().enumerated().map { index, script in
            SearchResult(
                id: "script:\(script.path)",
                providerID: .scripts,
                title: script.name,
                subtitle: (script.path as NSString).abbreviatingWithTildeInPath,
                icon: .symbol("terminal"),
                keywords: [],
                badge: "Script",
                action: .runScript(script.path),
                secondaryActions: [.copyText(script.path)],
                sortHint: index
            )
        }
    }
}

private actor ScriptTermination {
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func finish(with status: Int32) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: status)
        } else {
            self.status = status
        }
    }

    func wait() async -> Int32 {
        if let status {
            return status
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private nonisolated final class ScriptPipeCapture: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Never>?
    private var finished = false

    init(limit: Int) {
        self.limit = limit
        data.reserveCapacity(limit)
    }

    func setContinuation(_ continuation: CheckedContinuation<Data, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func append(_ chunk: Data) {
        lock.lock()
        let remaining = limit - data.count
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        let result = data
        lock.unlock()
        continuation.resume(returning: result)
    }
}
