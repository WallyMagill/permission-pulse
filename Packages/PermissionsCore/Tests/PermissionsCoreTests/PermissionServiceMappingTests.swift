import Foundation
import Testing
@testable import PermissionsCore

@Suite struct PermissionServiceMappingTests {
    @Test(arguments: [
        ("kTCCServiceAccessibility",              PermissionService.accessibility),
        ("kTCCServiceScreenCapture",              PermissionService.screenRecording),
        ("kTCCServiceSystemPolicyAllFiles",       PermissionService.fullDiskAccess),
        ("kTCCServiceMicrophone",                 PermissionService.microphone),
        ("kTCCServiceCamera",                     PermissionService.camera),
        ("kTCCServiceAppleEvents",                PermissionService.automation),
        ("kTCCServiceSystemPolicyDesktopFolder",  PermissionService.filesAndFolders),
        ("kTCCServiceSystemPolicyDocumentsFolder", PermissionService.filesAndFolders),
        ("kTCCServiceSystemPolicyDownloadsFolder", PermissionService.filesAndFolders),
        ("kTCCServiceSystemPolicyNetworkVolumes",  PermissionService.filesAndFolders),
        ("kTCCServiceSystemPolicyRemovableVolumes", PermissionService.filesAndFolders),
        ("kTCCServicePhotos",                     PermissionService.photos),
        ("kTCCServiceCalendar",                   PermissionService.calendar),
        ("kTCCServiceAddressBook",                PermissionService.contacts),
        ("kTCCServiceReminders",                  PermissionService.reminders),
        ("kTCCServiceBluetoothAlways",            PermissionService.bluetooth),
        ("kTCCServiceMediaLibrary",               PermissionService.mediaLibrary),
        ("kTCCServiceSystemPolicyAppBundles",     PermissionService.appManagement),
        ("kTCCServiceSystemPolicyAppData",        PermissionService.appManagement),
        ("kTCCServiceListenEvent",                PermissionService.inputMonitoring),
        ("kTCCServiceDeveloperTool",              PermissionService.developerTool),
    ])
    func mapsKnownTCCServiceStringsToExpectedCases(input: String, expected: PermissionService) {
        #expect(PermissionService(tccServiceString: input) == expected)
    }

    @Test(arguments: PermissionService.knownSkipped)
    func skippedServicesReturnNil(skipped: String) {
        #expect(PermissionService(tccServiceString: skipped) == nil)
    }

    @Test func unknownServiceReturnsNil() {
        #expect(PermissionService(tccServiceString: "kTCCServiceFutureThing") == nil)
    }

    @Test func knownSkippedContainsSixServices() {
        #expect(PermissionService.knownSkipped.count == 6)
    }
}
