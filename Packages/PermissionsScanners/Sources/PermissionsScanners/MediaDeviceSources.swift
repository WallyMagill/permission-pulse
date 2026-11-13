import CoreAudio
import CoreMediaIO
import Foundation

/// Audio devices with at least one input channel, via CoreAudio.
struct CoreAudioInputDevices: MediaDeviceSource {
    let queue: DispatchQueue

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func deviceIDs() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size) == 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &ids) == 0 else {
            return []
        }
        return ids.filter(hasInputStream)
    }

    func isRunning(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == 0 else {
            return false
        }
        return running != 0
    }

    func addRunningListener(
        _ id: AudioObjectID,
        onChange: @escaping @Sendable () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        add(onChange, to: id, selector: kAudioDevicePropertyDeviceIsRunningSomewhere)
    }

    func removeRunningListener(_ listener: @escaping AudioObjectPropertyListenerBlock, from id: AudioObjectID) {
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(id, &address, queue, listener)
    }

    func addDeviceListListener(onChange: @escaping @Sendable () -> Void) -> AudioObjectPropertyListenerBlock? {
        add(onChange, to: Self.systemObject, selector: kAudioHardwarePropertyDevices)
    }

    func removeDeviceListListener(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, queue, listener)
    }

    private func add(
        _ onChange: @escaping @Sendable () -> Void,
        to id: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyListenerBlock? {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        return AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == 0 ? block : nil
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
        return UnsafeMutableAudioBufferListPointer(bufferList).contains { $0.mNumberChannels > 0 }
    }
}

/// Cameras, via CoreMediaIO.
struct CoreMediaIOVideoDevices: MediaDeviceSource {
    let queue: DispatchQueue

    private static let systemObject = CMIOObjectID(kCMIOObjectSystemObject)

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    func deviceIDs() -> [CMIOObjectID] {
        var address = Self.address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size) == 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(Self.systemObject, &address, 0, nil, size, &size, &ids) == 0 else {
            return []
        }
        return ids
    }

    func isRunning(_ id: CMIOObjectID) -> Bool {
        var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(id, &address, 0, nil, size, &size, &running) == 0 else {
            return false
        }
        return running != 0
    }

    func addRunningListener(
        _ id: CMIOObjectID,
        onChange: @escaping @Sendable () -> Void
    ) -> CMIOObjectPropertyListenerBlock? {
        add(onChange, to: id, selector: kCMIODevicePropertyDeviceIsRunningSomewhere)
    }

    func removeRunningListener(_ listener: @escaping CMIOObjectPropertyListenerBlock, from id: CMIOObjectID) {
        var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        CMIOObjectRemovePropertyListenerBlock(id, &address, queue, listener)
    }

    func addDeviceListListener(onChange: @escaping @Sendable () -> Void) -> CMIOObjectPropertyListenerBlock? {
        add(onChange, to: Self.systemObject, selector: kCMIOHardwarePropertyDevices)
    }

    func removeDeviceListListener(_ listener: @escaping CMIOObjectPropertyListenerBlock) {
        var address = Self.address(kCMIOHardwarePropertyDevices)
        CMIOObjectRemovePropertyListenerBlock(Self.systemObject, &address, queue, listener)
    }

    private func add(
        _ onChange: @escaping @Sendable () -> Void,
        to id: CMIOObjectID,
        selector: Int
    ) -> CMIOObjectPropertyListenerBlock? {
        var address = Self.address(selector)
        let block: CMIOObjectPropertyListenerBlock = { _, _ in onChange() }
        return CMIOObjectAddPropertyListenerBlock(id, &address, queue, block) == 0 ? block : nil
    }
}
