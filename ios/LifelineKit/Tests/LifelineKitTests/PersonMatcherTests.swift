import Foundation
import Testing
@testable import LifelineKit

private func person(_ name: String) -> Person {
    Person(id: .init(), displayName: name, notes: nil, isOwner: false, birthDate: nil, birthDateOrigin: nil)
}

@Test func rankingPrefersCloseNamesThenKeepsTheRest() {
    let maya = person("Maya"), mai = person("Mai"), amy = person("Amy"), zed = person("Zed")
    let aliases: [PersonID: [String]] = [maya.id: ["my sister"], mai.id: [], amy.id: [], zed.id: []]
    let ranked = PersonMatcher.rank([zed, amy, mai, maya], aliases: aliases, for: "May")
    #expect(ranked.prefix(2).map(\.displayName) == ["Maya", "Mai"], "\(ranked.map(\.displayName))")
    #expect(ranked.count == 4)
    let bySister = PersonMatcher.rank([zed, amy, mai, maya], aliases: aliases, for: "my sister")
    #expect(bySister.first?.displayName == "Maya")
}
