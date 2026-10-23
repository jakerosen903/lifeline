import Foundation
import Testing
@testable import LifelineKit

@Test func inMemoryRoundTrip() throws {
    let store = InMemorySecretStore()
    #expect(try store.read(.anthropicAPIKey) == nil)
    try store.write("sk-ant-api03-abc", for: .anthropicAPIKey)
    #expect(try store.read(.anthropicAPIKey) == "sk-ant-api03-abc")
    try store.write("sk-ant-api03-def", for: .anthropicAPIKey)
    #expect(try store.read(.anthropicAPIKey) == "sk-ant-api03-def")
}

@Test func deleteRemoves() throws {
    let store = InMemorySecretStore()
    try store.write("x", for: .anthropicAPIKey)
    try store.delete(.anthropicAPIKey)
    #expect(try store.read(.anthropicAPIKey) == nil)
    try store.delete(.anthropicAPIKey)
}

@Test func apiKeyFormatRejectsBlankAndSpaces() {
    #expect(!APIKeyFormat.looksValid(""))
    #expect(!APIKeyFormat.looksValid("   "))
    #expect(!APIKeyFormat.looksValid("sk-ant-api03-abc def" + String(repeating: "a", count: 20)))
    #expect(!APIKeyFormat.looksValid("sk-live-" + String(repeating: "a", count: 40)))
    #expect(!APIKeyFormat.looksValid("sk-ant-short"))
}

@Test func apiKeyFormatAcceptsAConsoleKey() {
    #expect(APIKeyFormat.looksValid("sk-ant-api03-" + String(repeating: "a", count: 40)))
    #expect(APIKeyFormat.looksValid("  sk-ant-api03-" + String(repeating: "a", count: 40) + "\n"))
}
