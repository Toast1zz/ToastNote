import Foundation
import Testing
@testable import AIFormatKit

@Suite(.serialized) struct KeychainStoreTests {
    private let store = KeychainStore(service: "app.toastnote.ai.tests")
    private let account = "test-" + UUID().uuidString

    @Test func keychainRoundTrip() throws {
        defer { try? store.delete(account: account) }
        #expect(try store.get(account: account) == nil)
        try store.set("sk-test-123", account: account)
        #expect(try store.get(account: account) == "sk-test-123")
    }

    @Test func settingAgainOverwrites() throws {
        defer { try? store.delete(account: account) }
        try store.set("one", account: account)
        try store.set("two", account: account)
        #expect(try store.get(account: account) == "two")
    }

    @Test func deleteRemovesTheKey() throws {
        try store.set("x", account: account)
        try store.delete(account: account)
        #expect(try store.get(account: account) == nil)
    }

    @Test func deletingAMissingKeyIsNotAnError() throws {
        try store.delete(account: account)
    }
}
