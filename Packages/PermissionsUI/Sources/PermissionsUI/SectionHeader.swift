import SwiftUI

struct SectionHeader: View {
    let title: String
    let showsBadge: Bool
    let dataSource: AppViewModel.DataSource

    var body: some View {
        HStack {
            Text(title)
                .ppFont(.cardHeader)
            Spacer()
            if showsBadge {
                switch dataSource {
                case .mock: MockBadge()
                case .live: LiveBadge()
                }
            }
        }
    }
}
