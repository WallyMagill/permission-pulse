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

private final class FakeDeviceSource: MediaDeviceSource, @unchecked Sendable {
    typealias Listener = () -> Void

    private let lock = NSLock()
    private var present: [Int]
    private var running: Set<Int> = []
    private var runningListeners: [Int: Listener] = [:]
    private var listListener: Listener?
    private(set) var removedListeners: [Int] = []

    init(present: [Int]) {
        self.present = present
    }

    var watchedDevices: [Int] { lock.withLock { runningListeners.keys.sorted() } }
    var hasDeviceListListener: Bool { lock.withLock { listListener != nil } }

    func plugIn(_ id: Int) {
        let notify = lock.withLock { present.append(id); return listListener }
        notify?()
    }

    func unplug(_ id: Int) {
        let notify = lock.withLock { present.removeAll { $0 == id }; return listListener }
        notify?()
    }

    func setRunning(_ id: Int, _ isRunning: Bool) {
        let notify = lock.withLock { () -> Listener? in
            if isRunning { running.insert(id) } else { running.remove(id) }
            return runningListeners[id]
        }
        notify?()
    }

    func deviceIDs() -> [Int] { lock.withLock { present } }

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
