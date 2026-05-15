import Foundation

// Short, plain-English explanations of what each permission lets an app
// actually do. Used by the PermissionDetailSheet in v0.6.0+ to help users
// decide whether a grant is still warranted. Two- to three-sentence cap:
// scan, decide, move on.
extension PermissionService {
    public var riskDescription: String {
        switch self {
        case .accessibility:
            return String(localized: "Accessibility lets the app read the contents of any window on screen and simulate keyboard, mouse, and trackpad events as you. Granted apps can effectively impersonate you across the entire system. Common legitimate uses: window managers, text-expansion tools, and assistive software.")

        case .screenRecording:
            return String(localized: "Screen Recording lets the app capture anything visible on your displays — including other apps, video-call content, and any text or passwords on screen. Common legitimate uses: screenshot tools, conferencing apps, and screen-share helpers.")

        case .fullDiskAccess:
            return String(localized: "Full Disk Access lets the app read every file under your home folder plus protected system locations like Mail, Messages, Safari history, and the TCC database itself. It is the most powerful TCC grant. Common legitimate uses: backup tools, security utilities, and Permission Pulse itself.")

        case .microphone:
            return String(localized: "Microphone lets the app capture audio from any microphone, including built-in mics, AirPods, and external interfaces. Capture can happen silently in the background. Common legitimate uses: conferencing apps, voice notes, and dictation.")

        case .camera:
            return String(localized: "Camera lets the app capture video and stills from any connected camera. The hardware indicator light still lights up when the camera is in use, but the app can sample frames at will once granted. Common legitimate uses: conferencing apps, photo tools, and document scanners.")

        case .automation:
            return String(localized: "Automation lets the app send Apple Events to control another specific app — clicking buttons, reading data, or running scripts on its behalf. Each grant is scoped to one target app, shown on the row. Common legitimate uses: workflow automation, scripting tools, and integrations.")

        case .filesAndFolders:
            return String(localized: "Files and Folders gives per-folder read access to one of Desktop, Documents, Downloads, Network Volumes, or Removable Volumes. Narrower than Full Disk Access but still broad — every file inside the granted folder is readable. Common legitimate uses: editors and file-management tools.")

        case .photos:
            return String(localized: "Photos lets the app read your entire Photos library, including images, videos, location metadata, and any albums you've created. macOS may offer a 'limited access' variant; Permission Pulse shows whichever was granted. Common legitimate uses: photo editors and sharing tools.")

        case .calendar:
            return String(localized: "Calendar lets the app read every event in every calendar you've added to the system, including private notes and attendee lists. Some apps also gain write access to add or modify events. Common legitimate uses: meeting tools and calendar clients.")

        case .contacts:
            return String(localized: "Contacts lets the app read every entry in your address book — names, phone numbers, email addresses, birthdays, and notes. This is one of the most-exfiltrated pieces of data when granted to unvetted apps. Common legitimate uses: email clients, messaging apps, and CRM tools.")

        case .reminders:
            return String(localized: "Reminders lets the app read every reminder and list across every account you've added to the Reminders app. Some apps also gain write access. Common legitimate uses: task managers and productivity tools.")

        case .bluetooth:
            return String(localized: "Bluetooth lets the app scan for nearby Bluetooth devices and, depending on the grant variant, communicate with paired ones. Scanning can be used for proximity tracking in some contexts. Common legitimate uses: device-pairing utilities and audio software.")

        case .mediaLibrary:
            return String(localized: "Media Library lets the app read your Apple Music library and any music files imported into the Music app. Useful for music-related tools; rarely needed by anything else. Common legitimate uses: DJ software, music tagging tools, and party-playlist apps.")

        case .appManagement:
            return String(localized: "App Management lets the app modify, update, or delete other apps installed under /Applications. Common legitimate uses: app updaters, uninstallers, and developer tools. Grant carefully — a malicious app with this can replace any installed app's binary.")

        case .inputMonitoring:
            return String(localized: "Input Monitoring lets the app observe every keystroke and pointer event you make, system-wide, without needing focus or any visible indicator. This is effectively a keylogger capability. Common legitimate uses: text expansion tools, hotkey managers, and some accessibility software.")

        case .developerTool:
            return String(localized: "Developer Tools lets the app run code-signed or notarized binaries that would otherwise be blocked by macOS Gatekeeper and SIP. Typically granted only to IDEs and build tools. Grant only to apps from developer-tool vendors you trust.")
        }
    }
}
