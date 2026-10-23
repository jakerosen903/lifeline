import Foundation
import Testing
import GRDB
@testable import LifelineKit

@Test func savingProfileMirrorsOwnerPerson() throws {
    let db = try AppDatabase.inMemory(); let repo = ProfileRepository(db)
    try repo.save(Profile(displayName: "Rina", birthDate: .init(timeIntervalSince1970: 0),
                          birthPlaceText: "Oslo", freeText: nil, updatedAt: .now))
    let owner = try #require(try repo.owner())
    #expect(owner.isOwner && owner.displayName == "Rina" && owner.birthDateOrigin == .typed)
    try repo.save(Profile(displayName: "Rina B", birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    let ownerCount = try db.writer.read { try Int.fetchOne($0, sql: "select count(*) from person where is_owner = 1") }
    #expect(ownerCount == 1)
    #expect(try repo.owner()?.displayName == "Rina B")
    #expect(try repo.fetch()?.displayName == "Rina B")
}

@Test func emptyProfileStillCountsAsSaved() throws {
    let db = try AppDatabase.inMemory(); let repo = ProfileRepository(db)
    #expect(try repo.fetch() == nil)
    try repo.save(Profile(displayName: nil, birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now))
    #expect(try repo.fetch() != nil)
    #expect(try repo.owner()?.displayName == "")
}
