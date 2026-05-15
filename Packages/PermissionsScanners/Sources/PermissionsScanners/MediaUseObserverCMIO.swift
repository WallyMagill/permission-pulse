import CoreAudio
import CoreMediaIO
import Foundation
import OSLog
import PermissionsCore

public final class MediaUseObserverCMIO: MediaUseObserver, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "media-use-observer"
    )

    private let lock = NSLock()
    private var continuation: AsyncStream<MediaUseEvent>.Continuation?
    private let queue = DispatchQueue(
        label: "com.wallymagill.permissionpulse.mediause",
        qos: .utility
    )

    private var videoListeners: [(id: CMIOObjectID, block: CMIOObjectPropertyListenerBlock)] = []
    private var audioListeners: [(id: AudioObjectID, block: AudioObjectPropertyListenerBlock)] = []

    public init() {}

    deinit {
        tearDownListeners()
    }

    public func events() -> AsyncStream<MediaUseEvent> {
        AsyncStream { continuation in
            self.lock.withLock {
                self.continuation = continuation
            }

            self.startObservingVideo()
            self.startObservingAudio()
            self.emitInitialState()

            continuation.onTermination = { [weak self] _ in
                self?.tearDownListeners()
            }
        }
    }

    public func stop() async {
        let cont = lock.withLock { () -> AsyncStream<MediaUseEvent>.Continuation? in
            let c = continuation
            continuation = nil
            return c
        }
        cont?.finish()
    }

    private func startObservingVideo() {
        let ids = enumerateVideoDevices()
        for id in ids {
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.handleDeviceChange(.camera, isRunning: self?.queryVideoIsRunning(id) ?? false)
            }
            let status = CMIOObjectAddPropertyListenerBlock(id, &address, queue, block)
            guard status == 0 else {
                Self.logger.error("CMIO listener register failed for device \(id, privacy: .public): status=\(status, privacy: .public)")
                continue
            }
            lock.withLock {
                videoListeners.append((id: id, block: block))
            }
        }
    }

    private func startObservingAudio() {
        let ids = enumerateAudioInputDevices()
        for id in ids {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.handleDeviceChange(.microphone, isRunning: self?.queryAudioIsRunning(id) ?? false)
            }
            let status = AudioObjectAddPropertyListenerBlock(id, &address, queue, block)
            guard status == 0 else {
                Self.logger.error("CoreAudio listener register failed for device \(id, privacy: .public): status=\(status, privacy: .public)")
                continue
            }
            lock.withLock {
                audioListeners.append((id: id, block: block))
            }
        }
    }

    private func emitInitialState() {
        let videoIDs = lock.withLock { videoListeners.map(\.id) }
        let audioIDs = lock.withLock { audioListeners.map(\.id) }

        let cameraInUse = videoIDs.contains { queryVideoIsRunning($0) }
        let micInUse = audioIDs.contains { queryAudioIsRunning($0) }

        emit(MediaUseEvent(device: .camera, inUse: cameraInUse, timestamp: Date()))
        emit(MediaUseEvent(device: .microphone, inUse: micInUse, timestamp: Date()))
    }

    private func handleDeviceChange(_ device: MediaUseEvent.Device, isRunning: Bool) {
        let aggregate: Bool
        switch device {
        case .camera:
            let ids = lock.withLock { videoListeners.map(\.id) }
            aggregate = isRunning || ids.contains { queryVideoIsRunning($0) }
        case .microphone:
            let ids = lock.withLock { audioListeners.map(\.id) }
            aggregate = isRunning || ids.contains { queryAudioIsRunning($0) }
        }
        emit(MediaUseEvent(device: device, inUse: aggregate, timestamp: Date()))
    }

    private func emit(_ event: MediaUseEvent) {
        let cont = lock.withLock { continuation }
        cont?.yield(event)
    }

    private func tearDownListeners() {
        let (videos, audios) = lock.withLock { () -> ([(id: CMIOObjectID, block: CMIOObjectPropertyListenerBlock)], [(id: AudioObjectID, block: AudioObjectPropertyListenerBlock)]) in
            let v = videoListeners
            let a = audioListeners
            videoListeners.removeAll()
            audioListeners.removeAll()
            return (v, a)
        }

        for entry in videos {
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            CMIOObjectRemovePropertyListenerBlock(entry.id, &address, queue, entry.block)
        }
        for entry in audios {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(entry.id, &address, queue, entry.block)
        }
    }

    private func enumerateVideoDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &size, &ids) == 0 else {
            return []
        }
        return ids
    }

    private func enumerateAudioInputDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == 0 else {
            return []
        }
        return ids.filter { hasInputStream($0) }
    }

    private func hasInputStream(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == 0, size > 0 else {
            return false
        }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == 0 else {
            return false
        }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        return abl.contains { $0.mNumberChannels > 0 }
    }

    private func queryVideoIsRunning(_ id: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(id, &address, 0, nil, size, &size, &running) == 0 else {
            return false
        }
        return running != 0
    }

    private func queryAudioIsRunning(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == 0 else {
            return false
        }
        return running != 0
    }
}
