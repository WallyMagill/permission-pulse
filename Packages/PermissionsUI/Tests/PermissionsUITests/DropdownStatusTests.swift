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
        staleCount: Int = 0, appCount: Int = 42
    ) -> [DropdownStatusRow] {
        DropdownStatusBuilder.rows(
            attention: attention, micInUse: mic, cameraInUse: camera,
            changeCount: changeCount, hasUnreviewedChanges: hasUnreviewed,
            staleCount: staleCount, appCount: appCount
        )
    }

    @Test("All-clear shows only the summary row, routed to Overview")
    func allClear() {
        let result = rows()
        #expect(result.count == 1)
        #expect(result[0].kind == .allClear(appCount: 42))
        #expect(result[0].route == .overview)
    }

    @Test("Attention row leads and routes to the failing domain")
    func attentionFirst() {
        let result = rows(attention: .fdaDenied, changeCount: 3, hasUnreviewed: true)
        #expect(result.first?.kind == .attention(.fdaDenied))
        #expect(result.first?.route == .permissions(selectAppKey: nil))
        let btm = rows(attention: .btmOnlyFDADenied)
        #expect(btm.first?.route == .backgroundItems(selectID: nil))
        let la = rows(attention: .launchAgentError)
        #expect(la.first?.route == .launchAgents(selectID: nil))
        #expect(rows(attention: .degradedData).first?.route == .overview)
        #expect(rows(attention: .staleData).first?.route == .overview)
    }

    @Test("Media row appears while mic or camera is in use, routes to Permissions")
    func media() {
        let result = rows(mic: true)
        #expect(result.contains { $0.kind == .media(mic: true, camera: false) })
        #expect(result.first { $0.kind == .media(mic: true, camera: false) }?.route
            == .permissions(selectAppKey: nil))
    }

    @Test("Scan failure without history has a truthful Overview title and route")
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

        #expect(result.first?.route == .overview)
        #expect(result.first?.title == String(localized: "Scan failed — no results available"))
    }

    @Test("Changes and stale rows appear only with content; order is attention, media, changes, stale, summary")
    func ordering() {
        let result = rows(
            attention: .schemaMismatch, mic: true,
            changeCount: 3, hasUnreviewed: true, staleCount: 5
        )
        #expect(result.map(\.kind) == [
            .attention(.schemaMismatch),
            .media(mic: true, camera: false),
            .changes(count: 3),
            .stale(count: 5),
            .allClear(appCount: 42)
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
        #expect(title(.allClear(appCount: 1)) == "1 app with permissions")
        #expect(title(.allClear(appCount: 42)) == "42 apps with permissions")
    }
}
