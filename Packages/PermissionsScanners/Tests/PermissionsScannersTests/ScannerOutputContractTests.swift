import PermissionsCore
import Testing

@Suite struct ScannerOutputContractTests {
    @Test func scannerContractsAreSendableAndEquatable() {
        let warning = ScannerWarning(source: .entries, omittedCount: 2)
        let output = ScannerOutput(items: [1, 2], warnings: [warning])

        requireSendable(ScannerSource.userTCCDatabase)
        requireSendable(warning)
        requireSendable(output)
        #expect(output == ScannerOutput(items: [1, 2], warnings: [warning]))
        #expect(
            ScannerError.schemaMismatch(detail: "detail")
                == ScannerError.schemaMismatch(detail: "detail")
        )
    }
}

private func requireSendable<T: Sendable>(_: T) {}
