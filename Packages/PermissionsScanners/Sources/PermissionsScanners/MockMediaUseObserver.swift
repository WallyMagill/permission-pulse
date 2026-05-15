import Foundation
import PermissionsCore

public final class MockMediaUseObserver: MediaUseObserver {
    public init() {}

    public func events() -> AsyncStream<MediaUseEvent> {
        AsyncStream { continuation in
            let now = Date()
            continuation.yield(MediaUseEvent(device: .microphone, inUse: true, timestamp: now))
            continuation.yield(MediaUseEvent(device: .camera, inUse: true, timestamp: now))
            continuation.yield(MediaUseEvent(device: .microphone, inUse: false, timestamp: now))
            continuation.yield(MediaUseEvent(device: .camera, inUse: false, timestamp: now))
            continuation.finish()
        }
    }

    public func stop() async {}
}
