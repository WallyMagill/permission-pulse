import Foundation
import Testing
@testable import PermissionsScanners

@Suite struct MediaDeviceTrackerTests {
    @Test func deviceAddedAfterStartIsWatched() {
        let source = FakeDeviceSource(present: [1])
        let emitted = Emissions()
        let tracker = MediaDeviceTracker(source: source) { emitted.append($0) }
        tracker.start()

        source.plugIn(2)
        source.setRunning(2, true)

        #expect(source.watchedDevices == [1, 2])
        #expect(emitted.last == true)
    }

    @Test func deviceRemovedLosesItsListener() {
        let source = FakeDeviceSource(present: [1, 2])
        let tracker = MediaDeviceTracker(source: source) { _ in }
        tracker.start()

        source.unplug(2)

        #expect(source.watchedDevices == [1])
        #expect(source.removedListeners == [2])
    }

    @Test func deviceRemovedWhileInUseClearsTheIndicator() {
        let source = FakeDeviceSource(present: [1, 2])
        let emitted = Emissions()
        let tracker = MediaDeviceTracker(source: source) { emitted.append($0) }
        tracker.start()
        source.setRunning(2, true)
        #expect(emitted.last == true)

        // Only the device list fires; the vanished device sends no
        // running-state change and its stale state still reads as running.
        source.unplug(2)

        #expect(emitted.last == false)
    }

    // A device plugged in while start() reads the device list: its callback
    // must not be overtaken by start's older list, and the final state must
    // be the newer device's "in use".
    @Test func deviceListCallbackDuringStartIsAppliedLast() {
        let source = FakeDeviceSource(present: [1])
        let emitted = Emissions()
        let tracker = MediaDeviceTracker(source: source) { emitted.append($0) }
        source.whenDevicesFirstRead {
            source.plugIn(2)
            source.setRunning(2, true)
        }

        tracker.start()
        source.queue.sync {}

        #expect(source.watchedDevices == [1, 2])
        #expect(emitted.last == true)
    }

    @Test func stopRemovesEveryListener() {
        let source = FakeDeviceSource(present: [1, 2])
        let tracker = MediaDeviceTracker(source: source) { _ in }
        tracker.start()

        tracker.stop()

        #expect(source.watchedDevices.isEmpty)
        #expect(!source.hasDeviceListListener)
    }
}

private final class Emissions: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) { lock.withLock { values.append(value) } }
    var last: Bool? { lock.withLock { values.last } }
}

/// Delivers callbacks on its serial `queue` like CoreAudio and CoreMediaIO:
/// synchronously when the test drives it from outside, asynchronously when
/// a change happens while the queue is busy.
private final class FakeDeviceSource: MediaDeviceSource, @unchecked Sendable {
    typealias Listener = () -> Void

    let queue = DispatchQueue(label: "fake-media-devices")
    private let onQueue = DispatchSpecificKey<Bool>()
    private var onFirstDeviceRead: (() -> Void)?
    private let lock = NSLock()
    private var present: [Int]
    private var running: Set<Int> = []
    private var runningListeners: [Int: Listener] = [:]
    private var listListener: Listener?
    private(set) var removedListeners: [Int] = []

    init(present: [Int]) {
        self.present = present
        queue.setSpecific(key: onQueue, value: true)
    }

    /// Runs `change` right after the next device-list read has been taken.
    func whenDevicesFirstRead(_ change: @escaping () -> Void) {
        lock.withLock { onFirstDeviceRead = change }
    }

    var watchedDevices: [Int] { lock.withLock { runningListeners.keys.sorted() } }
    var hasDeviceListListener: Bool { lock.withLock { listListener != nil } }

    func plugIn(_ id: Int) {
        let notify = lock.withLock { present.append(id); return listListener }
        deliver(notify)
    }

    func unplug(_ id: Int) {
        let notify = lock.withLock { present.removeAll { $0 == id }; return listListener }
        deliver(notify)
    }

    func setRunning(_ id: Int, _ isRunning: Bool) {
        let notify = lock.withLock { () -> Listener? in
            if isRunning { running.insert(id) } else { running.remove(id) }
            return runningListeners[id]
        }
        deliver(notify)
    }

    private func deliver(_ callback: Listener?) {
        guard let callback else { return }
        if DispatchQueue.getSpecific(key: onQueue) == true {
            queue.async(execute: callback)
        } else {
            queue.sync(execute: callback)
        }
    }

    func deviceIDs() -> [Int] {
        let (ids, change) = lock.withLock { () -> ([Int], (() -> Void)?) in
            defer { onFirstDeviceRead = nil }
            return (present, onFirstDeviceRead)
        }
        change?()
        return ids
    }

    // Stale on purpose: a vanished device can still read as running.
    func isRunning(_ id: Int) -> Bool { lock.withLock { running.contains(id) } }

    func addRunningListener(_ id: Int, onChange: @escaping @Sendable () -> Void) -> Listener? {
        lock.withLock { runningListeners[id] = onChange }
        return onChange
    }

    func removeRunningListener(_ listener: @escaping Listener, from id: Int) {
        lock.withLock {
            runningListeners[id] = nil
            removedListeners.append(id)
        }
    }

    func addDeviceListListener(onChange: @escaping @Sendable () -> Void) -> Listener? {
        lock.withLock { listListener = onChange }
        return onChange
    }

    func removeDeviceListListener(_ listener: @escaping Listener) {
        lock.withLock { listListener = nil }
    }
}
