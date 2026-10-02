import Testing
@testable import VaultKit

@Suite struct VaultKitSmokeTests {
    @Test func moduleLoads() { #expect(true) }
}
