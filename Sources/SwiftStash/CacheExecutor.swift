import Dispatch

/// Runs a cache's work, including its storage engine's file I/O, on a serial dispatch queue.
///
/// Storage engines such as ``DiskStorageEngine`` block while reading and writing files.
/// Running each cache on its own queue keeps that blocking off the small cooperative thread
/// pool that Swift concurrency uses to run tasks.
final class CacheExecutor: SerialExecutor, @unchecked Sendable {
    // Unchecked: both properties are immutable after initialization, and DispatchSpecificKey
    // isn't marked Sendable.

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()

    init(label: String) {
        queue = DispatchQueue(label: label)
        queue.setSpecific(key: queueKey, value: ())
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async {
            job.runSynchronously(on: executor)
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    /// Whether the calling code runs on this executor's queue.
    var isCurrent: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }
}
