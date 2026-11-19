import Foundation
import Testing
@testable import LifelineKit

/// A fresh root with a database and a library, and a generated copy standing in for the one PhotoKit or the picker writes.
private final class Fixture: @unchecked Sendable {
    let root: URL
    let photos: PhotoRepository
    let library: PhotoLibrary

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cancellable-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        photos = ExtractionStore(db).photos
        library = PhotoLibrary(root: root, photos: photos)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func copy() throws -> URL {
        let url = root.appending(path: "picked-\(UUID().uuidString).jpg")
        try GeneratedPhoto.write(to: url, width: 400, height: 300, rgb: 0x5B7F3A, takenAt: "2019:07:14 10:00:00")
        return url
    }
}

@Test func aCancelDuringTheCopyStoresNothingAndRemovesTheCopy() async throws {
    let f = try Fixture()
    var cancelled = false
    var copy: URL?
    let stored = try await CancellablePhotoStore.fetchAndStore(fetch: {
        copy = try f.copy()
        cancelled = true   // the person closed the sheet while the copy was written
        return copy!
    }, assetLocalID: "invented/L0/001", into: f.library, isCancelled: { cancelled })
    #expect(stored == nil)
    #expect(try f.photos.fileNames().isEmpty, "no photo row")
    #expect(!FileManager.default.fileExists(atPath: try #require(copy).path), "the temporary copy goes")
}

@Test func withoutACancelThePhotoIsStoredAndTheCopyGoes() async throws {
    let f = try Fixture()
    var copy: URL?
    let stored = try await CancellablePhotoStore.fetchAndStore(fetch: {
        copy = try f.copy()
        return copy!
    }, assetLocalID: "invented/L0/001", into: f.library, isCancelled: { false })
    #expect(stored?.assetLocalID == "invented/L0/001")
    #expect(try f.photos.fileNames().count == 1)
    #expect(!FileManager.default.fileExists(atPath: try #require(copy).path))
}

@Test func aCancelledPickerFileIsNotStoredAndStaysWithItsOwner() async throws {
    let f = try Fixture()
    let file = try f.copy()
    let stored = try await CancellablePhotoStore.store(fileAt: file, assetLocalID: nil, into: f.library, isCancelled: { true })
    #expect(stored == nil)
    #expect(try f.photos.fileNames().isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.path), "the picker path removes its own copy")
}
