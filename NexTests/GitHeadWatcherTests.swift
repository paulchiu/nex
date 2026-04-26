import Foundation
@testable import Nex
import Testing

struct GitHeadWatcherTests {
    // MARK: - Helpers

    /// Spin up a fresh git repo in a temp dir and return its path. The repo
    /// is initialised on `main`, with one commit so HEAD is a valid ref
    /// (some git versions misbehave on a HEAD that's never been written).
    private static func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nex-head-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: dir)
        try runGit(["config", "user.email", "test@example.com"], at: dir)
        try runGit(["config", "user.name", "Test"], at: dir)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: dir)
        return dir
    }

    @discardableResult
    private static func runGit(_ args: [String], at dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func headPath(for worktree: URL) throws -> String {
        let raw = try runGit(["rev-parse", "--git-path", "HEAD"], at: worktree)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasPrefix("/")
            ? raw
            : (worktree.path as NSString).appendingPathComponent(raw)
    }

    /// Wait for the next event on the stream with a timeout. Returns true
    /// if an event arrived, false if the timeout elapsed first.
    private static func awaitEvent(
        _ stream: AsyncStream<Void>,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                _ = await iterator.next()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    // MARK: - Tests

    @Test func emitsOnDirectHeadWrite() async throws {
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let head = try Self.headPath(for: repo)
        let watcher = GitHeadWatcher()
        let id = UUID()
        let stream = watcher.start(associationID: id, headPath: head)
        defer { watcher.stop(associationID: id) }

        // Give the dispatch source a beat to register before we mutate.
        try await Task.sleep(for: .milliseconds(50))

        // Directly overwrite HEAD (simulates `git update-ref` style writes).
        try "ref: refs/heads/other\n".write(
            toFile: head,
            atomically: false,
            encoding: .utf8
        )

        let received = await Self.awaitEvent(stream)
        #expect(received, "watcher should emit on a direct HEAD write")
    }

    @Test func emitsOnGitCheckout() async throws {
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let head = try Self.headPath(for: repo)
        let watcher = GitHeadWatcher()
        let id = UUID()
        let stream = watcher.start(associationID: id, headPath: head)
        defer { watcher.stop(associationID: id) }

        try await Task.sleep(for: .milliseconds(50))

        // `git checkout -b` rewrites HEAD via temp-file + atomic rename.
        // The watcher needs to see this through its `.rename`/`.delete`
        // re-open dance.
        try Self.runGit(["checkout", "-b", "feature"], at: repo)

        let received = await Self.awaitEvent(stream)
        #expect(received, "watcher should emit on `git checkout -b`")
    }

    @Test func reopensAfterAtomicRenameForSubsequentWrites() async throws {
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let head = try Self.headPath(for: repo)
        let watcher = GitHeadWatcher()
        let id = UUID()
        let stream = watcher.start(associationID: id, headPath: head)
        defer { watcher.stop(associationID: id) }

        var iterator = stream.makeAsyncIterator()

        try await Task.sleep(for: .milliseconds(50))
        try Self.runGit(["checkout", "-b", "branch-a"], at: repo)
        _ = await iterator.next() // first checkout

        // After the rename re-arms (200ms), a second checkout should still
        // emit. This is the regression guard for the cancel-then-reopen
        // dance — without re-opening the fd, this second event would be
        // silently dropped.
        try await Task.sleep(for: .milliseconds(300))
        try Self.runGit(["checkout", "-b", "branch-b"], at: repo)

        let received = await Self.awaitEvent(stream)
        #expect(received, "watcher should still fire after re-arm")
    }

    @Test func stopHaltsFurtherEvents() async throws {
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let head = try Self.headPath(for: repo)
        let watcher = GitHeadWatcher()
        let id = UUID()
        let stream = watcher.start(associationID: id, headPath: head)

        watcher.stop(associationID: id)
        #expect(watcher.watchedCount == 0, "stop should evict the entry")

        // Mutate HEAD after stop. The stream should be finished, so
        // awaiting the next event yields nil immediately.
        try "ref: refs/heads/postcancel\n".write(
            toFile: head,
            atomically: false,
            encoding: .utf8
        )

        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        #expect(next == nil, "stream should be finished after stop")
    }

    @Test func startReplacesExistingEntryForSameID() async throws {
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let head = try Self.headPath(for: repo)
        let watcher = GitHeadWatcher()
        let id = UUID()

        let firstStream = watcher.start(associationID: id, headPath: head)
        let secondStream = watcher.start(associationID: id, headPath: head)
        defer { watcher.stop(associationID: id) }

        // The first stream should be terminated by the replacement.
        var firstIterator = firstStream.makeAsyncIterator()
        let firstNext = await firstIterator.next()
        #expect(firstNext == nil, "first stream should finish when replaced")

        try await Task.sleep(for: .milliseconds(50))
        try "ref: refs/heads/replaced\n".write(
            toFile: head,
            atomically: false,
            encoding: .utf8
        )

        let received = await Self.awaitEvent(secondStream)
        #expect(received, "second stream should receive the event")
        #expect(watcher.watchedCount == 1, "only one entry should remain")
    }

    @Test func stopAllEvictsEverything() throws {
        let repoA = try Self.makeRepo()
        let repoB = try Self.makeRepo()
        defer {
            try? FileManager.default.removeItem(at: repoA)
            try? FileManager.default.removeItem(at: repoB)
        }

        let watcher = GitHeadWatcher()
        // Hold the streams — dropping the AsyncStream finishes the
        // continuation, which fires our onTermination handler and would
        // drop the entries before we get a chance to call stopAll.
        let streamA = try watcher.start(associationID: UUID(), headPath: Self.headPath(for: repoA))
        let streamB = try watcher.start(associationID: UUID(), headPath: Self.headPath(for: repoB))
        #expect(watcher.watchedCount == 2)

        watcher.stopAll()
        #expect(watcher.watchedCount == 0)

        // Silence "unused" warnings — keeps the streams alive until here.
        _ = streamA
        _ = streamB
    }
}
