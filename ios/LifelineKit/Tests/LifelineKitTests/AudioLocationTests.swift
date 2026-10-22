import Foundation
import Testing
@testable import LifelineKit

@Test func audioDirectoryIsCreatedAndExcludedFromBackup() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let dir = try AudioLocation.directory(under: root)
    #expect(FileManager.default.fileExists(atPath: dir.path()))
    let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
    let id = SessionID()
    #expect(try AudioLocation.url(for: id, under: root).lastPathComponent == "\(id.rawValue).m4a")
}
