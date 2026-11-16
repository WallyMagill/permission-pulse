import Foundation
import OSLog
import PermissionsCore

/// Mic and camera in-use state from CoreAudio and CoreMediaIO
/// `…DeviceIsRunningSomewhere` listeners. Devices plugged in or removed after
/// launch are picked up through the hardware device-list properties.
public final class MediaUseObserverCMIO: MediaUseObserver, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "media-use-observer"
    )

    private let lock = NSLock()
    private var continuation: AsyncStream<MediaUseEvent>.Continuation?
    private var video: MediaDeviceTracker<CoreMediaIOVideoDevices>?
    private var audio: MediaDeviceTracker<CoreAudioInputDevices>?
    private let queue = DispatchQueue(
        label: "com.wallymagill.permissionpulse.mediause",
        qos: .utility
    )

    public init() {}

    deinit {
        tearDownListeners()
    }

    public func events() -> AsyncStream<MediaUseEvent> {
        AsyncStream { continuation in
            let video = MediaDeviceTracker(source: CoreMediaIOVideoDevices(queue: queue)) { [weak self] inUse in
                self?.emit(MediaUseEvent(device: .camera, inUse: inUse, timestamp: Date()))
            }
            let audio = MediaDeviceTracker(source: CoreAudioInputDevices(queue: queue)) { [weak self] inUse in
                self?.emit(MediaUseEvent(device: .microphone, inUse: inUse, timestamp: Date()))
            }
            lock.withLock {
                self.continuation = continuation
                self.video = video
                self.audio = audio
            }

            video.start()
            audio.start()

            let (v, a) = (video.coverage, audio.coverage)
            // A device without a listener is re-read only when another device of
            // its kind fires, so it can miss live updates on its own.
            if v.listening < v.present || a.listening < a.present {
                Self.logger.error("Media monitoring degraded — live updates may be missed (video \(v.listening)/\(v.present), audio \(a.listening)/\(a.present))")
            }

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

    private func emit(_ event: MediaUseEvent) {
        let cont = lock.withLock { continuation }
        cont?.yield(event)
    }

    private func tearDownListeners() {
        let (video, audio) = lock.withLock { () -> (MediaDeviceTracker<CoreMediaIOVideoDevices>?, MediaDeviceTracker<CoreAudioInputDevices>?) in
            let trackers = (self.video, self.audio)
            self.video = nil
            self.audio = nil
            return trackers
        }
        video?.stop()
        audio?.stop()
    }
}
