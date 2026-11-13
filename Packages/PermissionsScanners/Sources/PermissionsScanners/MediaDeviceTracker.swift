import Foundation
import OSLog

/// The hardware calls a `MediaDeviceTracker` makes for one kind of device
/// (audio inputs or cameras). A protocol so the bookkeeping can be tested
/// against a fake device list.
protocol MediaDeviceSource: Sendable {
    associatedtype DeviceID: Hashable & Sendable
    associatedtype Listener

    /// The serial queue every listener callback is delivered on.
    var queue: DispatchQueue { get }
    func deviceIDs() -> [DeviceID]
    func isRunning(_ id: DeviceID) -> Bool
    /// nil when the OS refuses the registration.
    func addRunningListener(_ id: DeviceID, onChange: @escaping @Sendable () -> Void) -> Listener?
    func removeRunningListener(_ listener: Listener, from id: DeviceID)
    /// Fires when devices are plugged in or removed. nil when refused.
    func addDeviceListListener(onChange: @escaping @Sendable () -> Void) -> Listener?
    func removeDeviceListListener(_ listener: Listener)
}

/// Keeps one running-state listener on every present device of one kind and
/// emits whether any of them is in use. When the device list changes it drops
/// listeners for devices that left, adds them for new ones, and re-emits, so a
/// device that disappears while in use cannot leave the indicator on.
///
/// Locking: `lock` guards the bookkeeping only. Hardware calls and `emit` run
/// outside it, because listener callbacks re-enter the tracker. Every refresh
/// and emission runs on `source.queue`, so device lists and in-use states are
/// applied in the order they were read.
final class MediaDeviceTracker<Source: MediaDeviceSource>: @unchecked Sendable {
    private static var logger: Logger {
        Logger(subsystem: "com.wallymagill.permissionpulse", category: "media-use-observer")
    }

    private let source: Source
    private let emit: @Sendable (Bool) -> Void
    private let lock = NSLock()
    private var devices: [Source.DeviceID] = []
    private var listeners: [Source.DeviceID: Source.Listener] = [:]
    private var deviceListListener: Source.Listener?
    private var stopped = false

    init(source: Source, emit: @escaping @Sendable (Bool) -> Void) {
        self.source = source
        self.emit = emit
    }

    /// Devices present vs. devices with a running-state listener.
    var coverage: (listening: Int, present: Int) {
        lock.withLock { (listeners.count, devices.count) }
    }

    /// Must not be called on `source.queue`: it waits for the first refresh there.
    func start() {
        dispatchPrecondition(condition: .notOnQueue(source.queue))
        let listListener = source.addDeviceListListener { [weak self] in self?.refresh() }
        if listListener == nil {
            Self.logger.error("Device-list listener refused; devices added later will not be watched")
        }
        let keep = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            deviceListListener = listListener
            return true
        }
        if !keep, let listListener { source.removeDeviceListListener(listListener) }
        source.queue.sync { refresh() }
    }

    func refresh() {
        let current = source.deviceIDs()
        let currentSet = Set(current)
        let change = lock.withLock { () -> (added: [Source.DeviceID], removed: [(Source.DeviceID, Source.Listener)])? in
            guard !stopped else { return nil }
            let removed = listeners.filter { !currentSet.contains($0.key) }
            for id in removed.keys { listeners[id] = nil }
            devices = current
            return (current.filter { listeners[$0] == nil }, removed.map { ($0.key, $0.value) })
        }
        guard let change else { return }
        for (id, listener) in change.removed { source.removeRunningListener(listener, from: id) }
        for id in change.added { register(id) }
        emitCombinedState()
    }

    func stop() {
        let (removed, listListener) = lock.withLock { () -> ([Source.DeviceID: Source.Listener], Source.Listener?) in
            let registered = (listeners, deviceListListener)
            stopped = true
            devices = []
            listeners = [:]
            deviceListListener = nil
            return registered
        }
        if let listListener { source.removeDeviceListListener(listListener) }
        for (id, listener) in removed { source.removeRunningListener(listener, from: id) }
    }

    private func register(_ id: Source.DeviceID) {
        guard let listener = source.addRunningListener(id, onChange: { [weak self] in self?.emitCombinedState() }) else {
            Self.logger.error("Running-state listener refused for a media device; it is polled on other callbacks only")
            return
        }
        // A concurrent refresh or stop may have raced this registration.
        let keep = lock.withLock { () -> Bool in
            guard !stopped, listeners[id] == nil, devices.contains(id) else { return false }
            listeners[id] = listener
            return true
        }
        if !keep { source.removeRunningListener(listener, from: id) }
    }

    private func emitCombinedState() {
        guard let ids = lock.withLock({ stopped ? nil : devices }) else { return }
        emit(ids.contains { source.isRunning($0) })
    }
}
