import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func scriptCatalogListsOnlySortedExecutableFiles() throws {
    let directory = try makeScriptsDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try writeScript(
        named: "2-first.command",
        body: "exit 0",
        in: directory
    )
    let later = try writeScript(
        named: "10-later.sh",
        body: "exit 0",
        in: directory
    )
    _ = try writeScript(
        named: "not-executable.sh",
        body: "exit 0",
        in: directory,
        executable: false
    )
    _ = try writeScript(
        named: ".hidden.sh",
        body: "exit 0",
        in: directory
    )
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("folder", isDirectory: true),
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o755]
    )

    let scripts = ScriptCatalog(directory: directory).scripts()

    #expect(scripts == [
        ScriptInfo(name: "2-first", path: first.path),
        ScriptInfo(name: "10-later", path: later.path)
    ])

    let missing = directory.appendingPathComponent("missing", isDirectory: true)
    #expect(ScriptCatalog(directory: missing).scripts().isEmpty)
}

@Test
func scriptRunnerCapturesSuccessfulOutput() async throws {
    let fixture = try makeRunnerFixture(body: "echo hello")
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let result = await ScriptRunner.run(
        scriptAt: fixture.script.path,
        workingDirectory: fixture.directory
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("hello"))
    #expect(result.launchFailure == nil)
}

@Test
func scriptRunnerReturnsExitCode() async throws {
    let fixture = try makeRunnerFixture(body: "exit 3")
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let result = await ScriptRunner.run(
        scriptAt: fixture.script.path,
        workingDirectory: fixture.directory
    )

    #expect(result.exitCode == 3)
    #expect(result.launchFailure == nil)
}

@Test(.timeLimit(.minutes(1)))
func scriptRunnerDrainsLargeStderrWithoutDeadlock() async throws {
    let body = """
    i=0
    while [ "$i" -lt 3500 ]; do
      echo 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!!' >&2
      i=$((i + 1))
    done
    exit 0
    """
    let fixture = try makeRunnerFixture(body: body)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let result = await ScriptRunner.run(
        scriptAt: fixture.script.path,
        workingDirectory: fixture.directory
    )

    #expect(result.exitCode == 0)
    #expect(result.stderr.utf8.count <= 65_536)
    #expect(result.launchFailure == nil)
}

@Test(.timeLimit(.minutes(1)))
func scriptRunnerGivesStdinImmediateEOF() async throws {
    let fixture = try makeRunnerFixture(body: "cat")
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let result = await ScriptRunner.run(
        scriptAt: fixture.script.path,
        workingDirectory: fixture.directory
    )

    #expect(result.exitCode == 0)
    #expect(result.launchFailure == nil)
}

@Test
func scriptRunnerClassifiesMissingShebang() async throws {
    let directory = try makeScriptsDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("no-shebang")
    try Data("plain text\n".utf8).write(to: script)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: script.path
    )

    let result = await ScriptRunner.run(
        scriptAt: script.path,
        workingDirectory: directory
    )

    #expect(result.exitCode == nil)
    #expect(result.launchFailure == .missingShebang)
}

@Test
func scriptRunnerUsesRequestedWorkingDirectory() async throws {
    let fixture = try makeRunnerFixture(body: "pwd")
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let result = await ScriptRunner.run(
        scriptAt: fixture.script.path,
        workingDirectory: fixture.directory
    )
    let printedPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let printedURL = URL(fileURLWithPath: printedPath).resolvingSymlinksInPath()
    let expectedURL = fixture.directory.resolvingSymlinksInPath()

    #expect(result.exitCode == 0)
    #expect(printedURL == expectedURL)
}

@MainActor
@Test
func scriptsProviderRequiresSearchAndMapsScripts() async throws {
    let directory = try makeScriptsDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = try writeScript(
        named: "deploy.sh",
        body: "exit 0",
        in: directory
    )
    let provider = ScriptsProvider(catalog: ScriptCatalog(directory: directory))

    let emptyResults = try await provider.results(
        for: ParsedQuery(mode: .general, term: "")
    )
    let otherModeResults = try await provider.results(
        for: ParsedQuery(mode: .fileSearch, term: "deploy")
    )
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "deploy")
    )

    #expect(emptyResults.isEmpty)
    #expect(otherModeResults.isEmpty)
    #expect(results.count == 1)
    #expect(results.first?.id == "script:\(script.path)")
    #expect(results.first?.providerID == .scripts)
    #expect(results.first?.title == "deploy")
    #expect(results.first?.subtitle == (script.path as NSString).abbreviatingWithTildeInPath)
    #expect(results.first?.icon == .symbol("terminal"))
    #expect(results.first?.keywords == [])
    #expect(results.first?.badge == "Script")
    #expect(results.first?.action == .runScript(script.path))
    #expect(results.first?.secondaryActions == [.copyText(script.path)])
    #expect(results.first?.sortHint == 0)
}

private func makeRunnerFixture(
    body: String
) throws -> (directory: URL, script: URL) {
    let directory = try makeScriptsDirectory()
    let script = try writeScript(named: "fixture.sh", body: body, in: directory)
    return (directory, script)
}

private func makeScriptsDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

@discardableResult
private func writeScript(
    named name: String,
    body: String,
    in directory: URL,
    executable: Bool = true
) throws -> URL {
    let script = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: script)
    try FileManager.default.setAttributes(
        [.posixPermissions: executable ? 0o755 : 0o644],
        ofItemAtPath: script.path
    )
    return script
}
