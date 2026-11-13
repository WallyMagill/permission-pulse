import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("DropdownStatusBuilder")
struct DropdownStatusTests {
    private func rows(
        attention: AttentionState = .clean,
        mic: Bool = false, camera: Bool = false,
        changeCount: Int = 0, hasUnreviewed: Bool = false,
        staleCount: Int = 0, appCount: Int? = 42, systemLevelOnly: Bool = false,
        translocated: Bool = false
    ) -> [DropdownStatusRow] {
        DropdownStatusBuilder.rows(
            attention: attention, micInUse: mic, cameraInUse: camera,
            changeCount: changeCount, hasUnreviewedChanges: hasUnreviewed,
            staleCount: staleCount, appCount: appCount, systemLevelOnly: systemLevelOnly,
            isTranslocated: translocated
        )
    }

    @Test("A translocated copy gets the move instruction right after any attention row")
    func translocated() {
        let result = rows(attention: .fdaDenied, mic: true, translocated: true)
        #expect(result.map(\.kind).prefix(3) == [.attention(.fdaDenied, .permissions), .moveToApplications, .media(mic: true, camera: false)])
        #expect(result[1].title == "Move Permission Pulse to your Applications folder, then open it from there.")
        #expect(!rows().contains { $0.kind == .moveToApplications })
    }

    @Test("Header says when the last scan finished: time today, date otherwise")
    func updatedText() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(ScanTimestamp.updatedText(lastScan: nil, now: now, calendar: calendar) == nil)
        let today = try #require(ScanTimestamp.updatedText(lastScan: now.addingTimeInterval(-60), now: now, calendar: calendar))
        let older = try #require(ScanTimestamp.updatedText(lastScan: now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar))
        #expect(today == "Updated \(now.addingTimeInterval(-60).formatted(date: .omitted, time: .shortened))")
        #expect(older.hasPrefix("Updated "))
        #expect(older.count > today.count)
    }

    @Test("All-clear shows only the summary row, routed to Overview")
    func allClear() {
        let result = rows()
        #expect(result.count == 1)
        #expect(result[0].kind == .summary(appCount: 42, systemLevelOnly: false, allClear: true))
        #expect(result[0].route == .overview)
    }

    @Test("The summary is an all-clear only when no other row needs attention")
    func summaryAllClearOnlyAlone() {
        let underWarning = rows(attention: .fdaDenied, appCount: 0)
        #expect(underWarning.last?.kind == .summary(appCount: 0, systemLevelOnly: false, allClear: false))
        let underStale = rows(staleCount: 2)
        #expect(underStale.last?.kind == .summary(appCount: 42, systemLevelOnly: false, allClear: false))
    }

    @Test("No permission data means no count row")
    func summaryOmittedWithoutData() {
        let result = rows(attention: .fdaDenied, appCount: nil)
        #expect(!result.contains { if case .summary = $0.kind { true } else { false } })
    }

    @Test("A reduced scope counts apps with system-level permissions")
    func summaryReducedScope() {
        let result = rows(appCount: 3, systemLevelOnly: true)
        #expect(result.last?.title == "3 apps with system-level permissions")
    }

    @Test("Attention row leads and routes to the failing domain")
    func attentionFirst() {
        let result = rows(attention: .fdaDenied, changeCount: 3, hasUnreviewed: true)
        #expect(result.first?.kind == .attention(.fdaDenied, .permissions))
        #expect(result.first?.route == .permissions(selectAppKey: nil))
        let btm = rows(attention: .btmOnlyFDADenied)
        #expect(btm.first?.route == .backgroundItems(selectID: nil))
        let la = rows(attention: .launchAgentError)
        #expect(la.first?.route == .launchAgents(selectID: nil))
        #expect(rows(attention: .degradedData([.launchAgents])).first?.route == .launchAgents(selectID: nil))
        #expect(rows(attention: .staleData([.backgroundItems])).first?.route == .backgroundItems(selectID: nil))
        #expect(rows(attention: .schemaMismatch([.backgroundItems])).first?.route == .backgroundItems(selectID: nil))
    }

    @Test("Each affected domain gets its own attention row and route")
    func attentionRowPerDomain() {
        let result = rows(attention: .staleData([.permissions, .backgroundItems]))
        #expect(result.prefix(2).map(\.route) == [.permissions(selectAppKey: nil), .backgroundItems(selectID: nil)])
        #expect(result[0].title == "Permissions: showing last-known data")
        #expect(result[1].title == "Background Items: showing last-known data")
        #expect(Set(result.map(\.id)).count == result.count)
    }

    @Test("With full scope the media row opens Permissions searched for the live device")
    func media() {
        let result = rows(mic: true)
        #expect(result.contains { $0.kind == .media(mic: true, camera: false) })
        #expect(result.first { $0.kind == .media(mic: true, camera: false) }?.route
            == .permissions(selectAppKey: nil, searchText: "Microphone"))
        #expect(rows(camera: true).first { $0.kind == .media(mic: false, camera: true) }?.route?.searchText
            == "Camera")
    }

    @Test("With reduced scope the media row opens System Settings, Microphone when both are live")
    func mediaReducedScope() {
        func destination(mic: Bool, camera: Bool) -> DropdownStatusRow.Destination? {
            rows(mic: mic, camera: camera, systemLevelOnly: true)
                .first { if case .media = $0.kind { true } else { false } }?.destination
        }
        #expect(destination(mic: false, camera: true) == .systemSettings(.camera))
        #expect(destination(mic: true, camera: false) == .systemSettings(.microphone))
        #expect(destination(mic: true, camera: true) == .systemSettings(.microphone))
    }

    @Test("Scan failure without history names the domain and routes to its page")
    func scanFailureTitleAndRoute() {
        let attention = AttentionState.evaluate(
            tccAvailability: .failed(
                lastSuccessful: nil,
                error: .temporarilyUnavailable(reason: "busy")
            ),
            btmAvailability: .complete(lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)),
            launchAgentAvailability: .complete(lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let result = rows(attention: attention)

        #expect(result.first?.route == .permissions(selectAppKey: nil))
        #expect(result.first?.title == "Permissions: scan failed — no results")
    }

    @Test("Changes and stale rows appear only with content; order is attention, media, changes, stale, summary")
    func ordering() {
        let result = rows(
            attention: .schemaMismatch([.permissions]), mic: true,
            changeCount: 3, hasUnreviewed: true, staleCount: 5
        )
        #expect(result.map(\.kind) == [
            .attention(.schemaMismatch([.permissions]), .permissions),
            .media(mic: true, camera: false),
            .changes(count: 3),
            .stale(count: 5),
            .summary(appCount: 42, systemLevelOnly: false, allClear: false)
        ])
        #expect(result[2].route == .recentChanges)
        #expect(result[3].route == .staleApps)
    }

    @Test("Reviewed changes don't produce a changes row")
    func reviewedChangesHidden() {
        let result = rows(changeCount: 3, hasUnreviewed: false)
        #expect(!result.contains { if case .changes = $0.kind { true } else { false } })
    }

    @Test("Count row titles agree in number at one and at many")
    func countTitlesPluralize() {
        func title(_ kind: DropdownStatusRow.Kind) -> String {
            DropdownStatusRow(kind: kind, route: .overview).title
        }
        #expect(title(.changes(count: 1)) == "1 change since your last review")
        #expect(title(.changes(count: 2)) == "2 changes since your last review")
        #expect(title(.stale(count: 1)) == "1 stale app with old permissions")
        #expect(title(.stale(count: 3)) == "3 stale apps with old permissions")
        #expect(title(.summary(appCount: 1, systemLevelOnly: false, allClear: true)) == "1 app with permissions")
        #expect(title(.summary(appCount: 42, systemLevelOnly: false, allClear: true)) == "42 apps with permissions")
        #expect(title(.summary(appCount: 1, systemLevelOnly: true, allClear: true)) == "1 app with system-level permissions")
    }
}
