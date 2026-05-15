import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct MockMediaUseObserverTests {
    @Test func emitsExpectedSequenceAndCompletes() async throws {
        let observer = MockMediaUseObserver()
        var collected: [MediaUseEvent] = []
        for await event in observer.events() {
            collected.append(event)
        }

        #expect(collected.count == 4)
        #expect(collected[0].device == .microphone)
        #expect(collected[0].inUse == true)
        #expect(collected[1].device == .camera)
        #expect(collected[1].inUse == true)
        #expect(collected[2].device == .microphone)
        #expect(collected[2].inUse == false)
        #expect(collected[3].device == .camera)
        #expect(collected[3].inUse == false)
    }

    @Test func stopIsSafeToCallAfterStreamCompletes() async {
        let observer = MockMediaUseObserver()
        for await _ in observer.events() {}
        await observer.stop()
    }

    @Test func eventEqualityWorks() {
        let now = Date()
        let a = MediaUseEvent(device: .microphone, inUse: true, timestamp: now)
        let b = MediaUseEvent(device: .microphone, inUse: true, timestamp: now)
        let c = MediaUseEvent(device: .camera, inUse: true, timestamp: now)
        #expect(a == b)
        #expect(a != c)
    }
}
