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
        let headPath: String
        let fileDescriptor: Int32
        let source: DispatchSourceFileSystemObject
        let continuation: AsyncStream<Void>.Continuation
    }

    private let lock = NSLock()
    /// nonisolated(unsafe) because all access is gated by `lock`.
    private nonisolated(unsafe) var entries: [UUID: Entry] = [:]
    /// Re-arm timers fired after a `.delete`/`.rename` event. Held so they
    /// can be cancelled if the association is stopped during the 200ms gap.
    private nonisolated(unsafe) var pendingReopens: [UUID: DispatchWorkItem] = [:]

    private let queue = DispatchQueue(label: "nex.git-head-watcher", qos: .utility)

    /// Begin watching `HEAD` for the given association. Calling `start`
    /// twice with the same `associationID` cancels the prior watcher and
    /// installs a new one — useful for `cancelInFlight` semantics in TCA.
    ///
    /// The returned stream emits `()` on each `HEAD` change (atomic-rename
    /// re-opens are handled internally — the consumer only sees the logical
    /// "HEAD changed" signal). Cancelling the consumer task stops the
    /// underlying watcher via the stream's termination handler.
    func start(associationID: UUID, headPath: String) -> AsyncStream<Void> {
        // Tear down any prior entry for this ID so callers don't have to.
        stop(associationID: associationID)

        return AsyncStream { continuation in
            guard let entry = makeEntry(
                associationID: associationID,
                headPath: headPath,
                continuation: continuation
            ) else {
                continuation.finish()
                return
            }

            lock.withLock { entries[associationID] = entry }

            continuation.onTermination = { [weak self] _ in
                self?.stop(associationID: associationID)
            }
        }
    }

    /// Stop watching for the given association. Idempotent.
    func stop(associationID: UUID) {
        let removedEntry: Entry? = lock.withLock {
            entries.removeValue(forKey: associationID)
        }
        let removedReopen: DispatchWorkItem? = lock.withLock {
            pendingReopens.removeValue(forKey: associationID)
        }
        // `cancel` triggers the source's cancel handler, which closes the fd.
        removedEntry?.source.cancel()
        removedEntry?.continuation.finish()
        removedReopen?.cancel()
    }

    /// Stop all watchers. Used on app teardown.
    func stopAll() {
        let allIDs: [UUID] = lock.withLock { Array(entries.keys) }
        for id in allIDs {
            stop(associationID: id)
        }
    }

    var watchedCount: Int {
        lock.withLock { entries.count }
    }

    // MARK: - Internal

    private func makeEntry(
        associationID: UUID,
        headPath: String,
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
                scheduleReopen(associationID: associationID, headPath: headPath)
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        return Entry(
            headPath: headPath,
            fileDescriptor: fd,
            source: source,
            continuation: continuation
        )
    }

    private func scheduleReopen(associationID: UUID, headPath: String) {
        // Cancel the current source — the cancel handler will close the fd.
        // We keep the continuation alive so the consumer sees the next event
        // through the same stream.
        let prior: Entry? = lock.withLock {
            entries.removeValue(forKey: associationID)
        }
        prior?.source.cancel()

        guard let continuation = prior?.continuation else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Remove ourselves from the pending map before re-arming so a
            // racing `stop` after this point can still cancel cleanly.
            lock.withLock { _ = pendingReopens.removeValue(forKey: associationID) }

            guard let next = makeEntry(
                associationID: associationID,
                headPath: headPath,
                continuation: continuation
            ) else {
                // The HEAD file disappeared and didn't reappear. End the
                // stream so the consuming TCA effect exits its for-await
                // loop instead of hanging forever.
                continuation.finish()
                return
            }
            lock.withLock { entries[associationID] = next }
        }

        lock.withLock { pendingReopens[associationID] = work }
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
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
