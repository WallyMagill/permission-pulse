import Testing
import SwiftUI
import PermissionsCore
@testable import PermissionsUI

@Suite("DesignSystem")
struct DesignSystemTests {
    @Test("every badge style passes WCAG AA (>= 4.5:1)")
    func badgeContrast() {
        for style in [PPBadgeStyle.mock, .live, .enabled, .disabled, .dispositionUnknown] {
            let ratio = WCAGContrast.ratio(
                foreground: style.foregroundRGB,
                background: style.backgroundRGB
            )
            #expect(ratio >= 4.5, "\(style) contrast \(ratio) < 4.5")
        }
    }

    @Test("dropdown clamp caps large sizes but passes small ones through")
    func clamp() {
        #expect(PPDynamicType.clampedForDropdown(.accessibility5) == .xLarge)
        #expect(PPDynamicType.clampedForDropdown(.small) == .small)
        #expect(PPDynamicType.clampedForDropdown(.xLarge) == .xLarge)
    }
}
