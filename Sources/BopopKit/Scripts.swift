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
    private nonisolated static let drainDeadline: Duration = .seconds(2)
    private nonisolated static let truncationMarker =
        "(output truncated: descendant still holds the pipe)"

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
        let stdoutCapture = ScriptPipeCapture(limit: outputLimit)
        let stderrCapture = ScriptPipeCapture(limit: outputLimit)
        // These three all start immediately, concurrently, right after
        // launch: the drains MUST be attached before (or at worst,
        // alongside) waiting for termination, or a script that writes
        // enough output to fill the pipe buffer would block inside its own
        // write() call — and since it's blocked, it would never reach its
        // own exit(), so termination.wait() would hang too.
        async let stdoutData = drain(stdoutHandle, into: stdoutCapture)
        async let stderrData = drain(stderrHandle, into: stderrCapture)
        async let terminationStatus = termination.wait()

        let exitCode = await terminationStatus

        // A descendant process that inherited the pipe's write end (e.g. a
        // backgrounded `sleep 30 &`) keeps it open even after the script's
        // own process has exited, so the readabilityHandler-driven drains
        // above may never see EOF on their own. Race them against a
        // deadline measured from termination — a well-behaved script has
        // already produced all its output by the time it exits, so this
        // costs nothing in the common case — rather than let a lingering
        // descendant hang `run()` forever. The watchdog is a plain
        // unstructured Task (not a TaskGroup child), so cancelling it below
        // doesn't require this function to block on it first: if the
        // drains finish naturally, `watchdog.cancel()` just turns its sleep
        // into a no-op; if the deadline wins, it forces both captures to
        // resume with whatever they've captured so far and clears the
        // handlers so the OS stops invoking them.
        let watchdog = Task<Bool, Never> {
            try? await Task.sleep(for: drainDeadline)
            guard !Task.isCancelled else {
                return false
            }
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            stdoutCapture.finish()
            stderrCapture.finish()
            return true
        }

        let capturedStdout = await stdoutData
        let capturedStderr = await stderrData
        watchdog.cancel()
        let timedOut = await watchdog.value

        var stderrString = String(decoding: capturedStderr, as: UTF8.self)
        if timedOut {
            stderrString += stderrString.isEmpty ? truncationMarker : "\n\(truncationMarker)"
        }

        return ScriptRunResult(
            exitCode: exitCode,
            stdout: String(decoding: capturedStdout, as: UTF8.self),
            stderr: stderrString,
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

    private static nonisolated func drain(
        _ fileHandle: FileHandle,
        into capture: ScriptPipeCapture
    ) async -> Data {
        // On macOS 15.7, AsyncBytes did not yield live pipe data before EOF.
        await withCheckedContinuation { continuation in
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
