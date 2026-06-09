import Testing
@testable import PermissionsCore

@Suite("WCAGContrast")
struct WCAGContrastTests {
    @Test("black on white is 21:1") func extreme() {
        let r = WCAGContrast.ratio(foreground: (0, 0, 0), background: (1, 1, 1))
        #expect(abs(r - 21.0) < 0.1)
    }
    @Test("identical colors are 1:1") func identical() {
        let r = WCAGContrast.ratio(foreground: (0.5, 0.5, 0.5), background: (0.5, 0.5, 0.5))
        #expect(abs(r - 1.0) < 0.001)
    }
    @Test("ratio is symmetric") func symmetric() {
        let a = WCAGContrast.ratio(foreground: (0.1, 0.2, 0.3), background: (0.9, 0.8, 0.7))
        let b = WCAGContrast.ratio(foreground: (0.9, 0.8, 0.7), background: (0.1, 0.2, 0.3))
        #expect(abs(a - b) < 0.001)
    }
}
