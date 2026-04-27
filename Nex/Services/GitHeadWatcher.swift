import ComposableArchitecture
import Foundation

/// Watches the `HEAD` file for each registered `RepoAssociation` and emits
/// a stream event whenever it changes. Used to drive sub-second sidebar
/// updates after `git checkout`, `git switch`, `git reset`, etc.
///
/// At rest this costs zero CPU — `kqueue` only wakes the dispatch queue on
/// actual filesystem events. Per watcher: one open file descriptor + a
/// `DispatchSourceFileSystemObject`.
final class GitHeadWatcher: Sendable {
    private struct Entry {
        let token: UUID
        let headPath: String
        let fileDescriptor: Int32
        let source: DispatchSourceFileSystemObject
        let continuation: AsyncStream<Void>.Continuation
    }

    private struct PendingReopen {
        let token: UUID
        let workItem: DispatchWorkItem
        let continuation: AsyncStream<Void>.Continuation
    }

    private struct RemovedWatch {
        let entry: Entry?
        let pendingReopen: PendingReopen?
    }

    private let lock = NSLock()
    /// nonisolated(unsafe) because all access is gated by `lock`.
    private nonisolated(unsafe) var entries: [UUID: Entry] = [:]
    /// Re-arm timers fired after a `.delete`/`.rename` event. Held so they
    /// can be cancelled if the association is stopped during the 200ms gap.
    private nonisolated(unsafe) var pendingReopens: [UUID: PendingReopen] = [:]
    /// Per-start generation tokens. AsyncStream termination and delayed
    /// reopens only tear down the watcher that created them.
    private nonisolated(unsafe) var tokens: [UUID: UUID] = [:]

    private let queue = DispatchQueue(label: "nex.git-head-watcher", qos: .utility)
    private let reopenDelay: DispatchTimeInterval

    init(reopenDelay: DispatchTimeInterval = .milliseconds(200)) {
        self.reopenDelay = reopenDelay
    }

    /// Begin watching `HEAD` for the given association. Calling `start`
    /// twice with the same `associationID` cancels the prior watcher and
    /// installs a new one — useful for `cancelInFlight` semantics in TCA.
    ///
    /// The returned stream emits `()` on each `HEAD` change (atomic-rename
    /// re-opens are handled internally — the consumer only sees the logical
    /// "HEAD changed" signal). Cancelling the consumer task stops the
    /// underlying watcher via the stream's termination handler.
    func start(associationID: UUID, headPath: String) -> AsyncStream<Void> {
        let token = UUID()
        let removed = lock.withLock {
            tokens[associationID] = token
            return removeLocked(associationID: associationID)
        }
        tearDown(removed, finishContinuation: true)

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.stop(associationID: associationID, token: token)
            }

            guard let entry = makeEntry(
                associationID: associationID,
                headPath: headPath,
                token: token,
                continuation: continuation
            ) else {
                lock.withLock {
                    if tokens[associationID] == token {
                        tokens.removeValue(forKey: associationID)
                    }
                }
                continuation.finish()
                return
            }

            let installed = lock.withLock {
                guard tokens[associationID] == token else { return false }
                entries[associationID] = entry
                return true
            }
            if !installed {
                entry.source.cancel()
                continuation.finish()
            }
        }
    }

    /// Stop watching for the given association. Idempotent.
    func stop(associationID: UUID) {
        let removed = lock.withLock {
            tokens.removeValue(forKey: associationID)
            return removeLocked(associationID: associationID)
        }
        // `cancel` triggers the source's cancel handler, which closes the fd.
        tearDown(removed, finishContinuation: true)
    }

    /// Stop all watchers. Used on app teardown.
    func stopAll() {
        let removed: [RemovedWatch] = lock.withLock {
            tokens.removeAll()
            let active = entries.values.map { RemovedWatch(entry: $0, pendingReopen: nil) }
            let pending = pendingReopens.values.map { RemovedWatch(entry: nil, pendingReopen: $0) }
            entries.removeAll()
            pendingReopens.removeAll()
            return active + pending
        }
        for watch in removed {
            tearDown(watch, finishContinuation: true)
        }
    }

    var watchedCount: Int {
        lock.withLock { entries.count }
    }

    var pendingReopenCount: Int {
        lock.withLock { pendingReopens.count }
    }

    // MARK: - Internal

    private func makeEntry(
        associationID: UUID,
        headPath: String,
        token: UUID,
        continuation: AsyncStream<Void>.Continuation
    ) -> Entry? {
        let fd = open(headPath, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            // Always emit so the consumer knows HEAD changed. `git checkout`
            // typically writes HEAD via a temp file + atomic rename, so we'll
            // see one event with `.rename`/`.delete`. `git update-ref` and
            // some other tools just write in place (`.write`).
            continuation.yield()
            if flags.contains(.delete) || flags.contains(.rename) {
                scheduleReopen(
                    associationID: associationID,
                    headPath: headPath,
                    token: token,
                    continuation: continuation
                )
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        return Entry(
            token: token,
            headPath: headPath,
            fileDescriptor: fd,
            source: source,
            continuation: continuation
        )
    }

    private func scheduleReopen(
        associationID: UUID,
        headPath: String,
        token: UUID,
        continuation: AsyncStream<Void>.Continuation
    ) {
        let work = DispatchWorkItem { [weak self] in
            self?.performReopen(
                associationID: associationID,
                headPath: headPath,
                token: token,
                continuation: continuation
            )
        }

        // Cancel the current source — the cancel handler will close the fd.
        // We keep the continuation alive so the consumer sees the next event
        // through the same stream. The pending work item is installed under
        // the same lock as removing the active entry, so `stop` cannot miss
        // the watcher during the 200ms re-open gap.
        let prior: Entry? = lock.withLock {
            guard tokens[associationID] == token,
                  let current = entries[associationID],
                  current.token == token else { return nil }
            entries.removeValue(forKey: associationID)
            pendingReopens[associationID] = PendingReopen(
                token: token,
                workItem: work,
                continuation: continuation
            )
            return current
        }

        guard let prior else {
            work.cancel()
            return
        }

        prior.source.cancel()
        queue.asyncAfter(deadline: .now() + reopenDelay, execute: work)
    }

    private func performReopen(
        associationID: UUID,
        headPath: String,
        token: UUID,
        continuation: AsyncStream<Void>.Continuation
    ) {
        let shouldAttempt = lock.withLock {
            tokens[associationID] == token
                && pendingReopens[associationID]?.token == token
        }
        guard shouldAttempt else { return }

        guard let next = makeEntry(
            associationID: associationID,
            headPath: headPath,
            token: token,
            continuation: continuation
        ) else {
            let shouldFinish = lock.withLock {
                guard tokens[associationID] == token,
                      pendingReopens[associationID]?.token == token else {
                    return false
                }
                tokens.removeValue(forKey: associationID)
                pendingReopens.removeValue(forKey: associationID)
                return true
            }
            if shouldFinish {
                continuation.finish()
            }
            return
        }

        let installed = lock.withLock {
            guard tokens[associationID] == token,
                  pendingReopens[associationID]?.token == token else {
                return false
            }
            pendingReopens.removeValue(forKey: associationID)
            entries[associationID] = next
            return true
        }

        if !installed {
            next.source.cancel()
            continuation.finish()
        }
    }

    private func stop(associationID: UUID, token: UUID) {
        let removed = lock.withLock {
            guard tokens[associationID] == token else {
                return RemovedWatch(entry: nil, pendingReopen: nil)
            }
            tokens.removeValue(forKey: associationID)
            return removeLocked(associationID: associationID)
        }
        tearDown(removed, finishContinuation: true)
    }

    private func removeLocked(associationID: UUID) -> RemovedWatch {
        let entry = entries.removeValue(forKey: associationID)
        let pendingReopen = pendingReopens.removeValue(forKey: associationID)
        return RemovedWatch(entry: entry, pendingReopen: pendingReopen)
    }

    private func tearDown(_ removed: RemovedWatch, finishContinuation: Bool) {
        removed.entry?.source.cancel()
        removed.pendingReopen?.workItem.cancel()
        if finishContinuation {
            removed.entry?.continuation.finish()
            removed.pendingReopen?.continuation.finish()
        }
    }
}

// MARK: - TCA Dependency

extension GitHeadWatcher: DependencyKey {
    static let liveValue = GitHeadWatcher()
    static let testValue = GitHeadWatcher()
}

extension DependencyValues {
    var gitHeadWatcher: GitHeadWatcher {
        get { self[GitHeadWatcher.self] }
        set { self[GitHeadWatcher.self] = newValue }
    }
}
