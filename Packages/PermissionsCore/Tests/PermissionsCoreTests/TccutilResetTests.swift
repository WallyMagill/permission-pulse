import Testing
@testable import PermissionsCore

@Suite("tccutil reset mapping")
struct TccutilResetTests {
    @Test("known services map to their tccutil service name")
    func knownMappings() {
        #expect(PermissionService.screenRecording.tccutilServiceName == "ScreenCapture")
        #expect(PermissionService.fullDiskAccess.tccutilServiceName == "SystemPolicyAllFiles")
        #expect(PermissionService.contacts.tccutilServiceName == "AddressBook")
        #expect(PermissionService.inputMonitoring.tccutilServiceName == "ListenEvent")
    }

    @Test("filesAndFolders has no single canonical reset command")
    func filesAndFoldersIsNil() {
        #expect(PermissionService.filesAndFolders.tccutilServiceName == nil)
    }

    @Test("every service except filesAndFolders has a tccutil name")
    func everyServiceExceptFilesAndFolders() {
        for service in PermissionService.allCases where service != .filesAndFolders {
            #expect(service.tccutilServiceName != nil, "\(service) is missing a tccutil name")
        }
    }

    @Test("builds one sorted command per mappable service for an app")
    func buildsCommands() {
        let cmds = PermissionService.tccutilResetCommands(
            bundleID: "com.foo.bar",
            services: [.camera, .screenRecording, .filesAndFolders]
        )
        #expect(cmds == [
            "tccutil reset Camera com.foo.bar",
            "tccutil reset ScreenCapture com.foo.bar",
        ])
    }

    @Test("no commands when bundle ID is empty")
    func emptyBundleID() {
        #expect(PermissionService.tccutilResetCommands(bundleID: "", services: [.camera]).isEmpty)
    }
}
