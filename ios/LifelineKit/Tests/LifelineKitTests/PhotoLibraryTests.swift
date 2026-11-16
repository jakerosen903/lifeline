import Foundation
import ImageIO
import Testing
@testable import LifelineKit

/// A fresh root in the temporary folder, a file database, and the people and the memory the tests hang photos on.
private final class Fixture: @unchecked Sendable {
    let root: URL
    let store: ExtractionStore
    let library: PhotoLibrary
    let photosDir: URL
    let maya: Entity, dad: Entity
    let treeHouse: Memory
    let session: SessionID

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "photo-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        let db = try AppDatabase.open(at: root.appending(path: "Lifeline/lifeline.sqlite"))
        store = ExtractionStore(db)
        photosDir = try PhotoLocation.directory(under: root)
        library = PhotoLibrary(root: root, photos: store.photos)
        maya = try store.entities.insert(type: .person, title: "Maya")
        dad = try store.entities.insert(type: .person, title: "Dad")
        let (s1, segments) = try StoreFixtures.session(in: store.sessions, segments: ["the tree house"])
        session = s1
        treeHouse = try StoreFixtures.memory(in: store.memories, candidates: store.candidates, segment: segments[0].id, title: "The tree house")
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A generated source image under the root's `sources` folder.
    func source(_ name: String = "source", width: Int = 3000, height: Int = 2000, rgb: Int = 0xE07A2E, takenAt: String? = nil,
                gps: (lat: Double, lon: Double)? = nil, orientation: Int = 1, alpha: Bool = false) throws -> URL {
        let folder = root.appending(path: "sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).\(alpha ? "png" : "jpg")")
        try GeneratedPhoto.write(to: url, width: width, height: height, rgb: rgb, takenAt: takenAt, gps: gps, orientation: orientation, alpha: alpha)
        return url
    }

    var photoFiles: [String] { (try? FileManager.default.contentsOfDirectory(atPath: photosDir.path))?.sorted() ?? [] }
}

private func properties(of file: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

// MARK: - Add

@Test func addStoresADownscaledCopyWithNoMetadata() async throws {
    let f = try Fixture()
    let source = try f.source(takenAt: "2012:06:14 15:32:10", gps: (0.5, -30.0), orientation: 6)
    let photo = try await f.library.add(fileAt: source, assetLocalID: "invented/L0/001", to: .entity(f.maya.id), now: Date(timeIntervalSince1970: 1_700_000_000))
    let stored = f.library.url(for: photo)
    #expect(stored.lastPathComponent == "\(photo.id.rawValue).jpg")
    #expect(max(photo.pixelWidth, photo.pixelHeight) == 2048 && photo.pixelWidth < photo.pixelHeight, "the rotation is in the pixels")
    let props = try properties(of: stored)
    #expect(props[kCGImagePropertyGPSDictionary] == nil, "no GPS in the stored file")
    #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
    #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    #expect(props[kCGImagePropertyHasAlpha] as? Bool != true)
    #expect(photo.takenAt?.stored == "2012-06-14T15:32:10" && photo.takenOrigin == .exif)
    #expect(photo.lat == 0.5 && photo.lon == -30.0 && photo.locationOrigin == .exif)
    #expect(photo.assetLocalID == "invented/L0/001" && photo.sha256.count == 64)
    #expect(try f.store.photos.photos(of: .entity(f.maya.id)).map(\.isCover) == [true])
    #expect(try f.store.photos.photo(id: photo.id) == photo, "the row says what the file is")
}

@Test func aPhotoLocationIsNeverAPlace() async throws {
    let f = try Fixture()
    let places = try f.store.entities.entities(type: .place).count, memories = try f.store.memories.allMemories()
    _ = try await f.library.add(fileAt: try f.source(gps: (51.5, -0.12)), assetLocalID: nil, to: .memory(f.treeHouse.id))
    #expect(try f.store.entities.entities(type: .place).count == places)
    #expect(try f.store.memories.allMemories() == memories, "no memory's range or place changes")
}

@Test func aPhotoWithoutMetadataStoresNone() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    #expect(photo.takenAt == nil && photo.takenOrigin == nil && photo.lat == nil && photo.lon == nil && photo.locationOrigin == nil)
}

@Test func aSmallPhotoIsNotEnlarged() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(width: 800, height: 600), assetLocalID: nil, to: .entity(f.maya.id))
    #expect((photo.pixelWidth, photo.pixelHeight) == (800, 600))
}

@Test func aHugeImageIsStoredAtMost2048Pixels() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(width: 12_000, height: 1_500), assetLocalID: nil, to: .entity(f.maya.id))
    #expect(photo.pixelWidth == 2048 && photo.pixelHeight == 256)
}

@Test func aTransparentImageIsStoredOnWhite() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(width: 400, height: 300, alpha: true), assetLocalID: nil, to: .entity(f.maya.id))
    #expect(try properties(of: f.library.url(for: photo))[kCGImagePropertyHasAlpha] as? Bool != true)
}

@Test func aFileThatIsNotAPhotoStoresNothing() async throws {
    let f = try Fixture()
    let bogus = f.root.appending(path: "bogus.jpg")
    try Data("this is not a photo".utf8).write(to: bogus)
    await #expect(throws: PhotoImport.Error.unreadable) { try await f.library.add(fileAt: bogus, assetLocalID: nil, to: .entity(f.maya.id)) }
    #expect(f.photoFiles.isEmpty)
    #expect(try f.store.photos.photos(of: .entity(f.maya.id)).isEmpty)
    #expect(PhotoImport.Error.unreadable.localizedDescription == "Lifeline cannot read this file as a photo.")
}

@Test func aWriteThatFailsStoresNothing() async throws {
    let f = try Fixture()
    let source = try f.source()
    // A folder the app cannot write to is a full disk, as far as a test can make one.
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.photosDir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.photosDir.path) }
    await #expect(throws: (any Error).self) { try await f.library.add(fileAt: source, assetLocalID: nil, to: .entity(f.maya.id)) }
    #expect(try f.store.photos.photos(of: .entity(f.maya.id)).isEmpty)
    #expect(try f.store.photos.fileNames().isEmpty)
    #expect(f.photoFiles.isEmpty)
}

@Test func theSamePhotoTwiceKeepsOneCopy() async throws {
    let f = try Fixture()
    let source = try f.source()
    let first = try await f.library.add(fileAt: source, assetLocalID: nil, to: .entity(f.maya.id))
    let second = try await f.library.add(fileAt: source, assetLocalID: nil, to: .entity(f.dad.id))
    _ = try await f.library.add(fileAt: source, assetLocalID: nil, to: .entity(f.maya.id))
    #expect(second.id == first.id)
    #expect(f.photoFiles == ["\(first.id.rawValue).jpg"])
    #expect(try f.store.photos.photos(of: .entity(f.maya.id)).count == 1)
    #expect(try f.store.photos.photos(of: .entity(f.dad.id)).count == 1)
}

// MARK: - Remove and cover

@Test func removeDeletesTheFileWhenNoPageIsLeft() async throws {
    let f = try Fixture()
    let first = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    _ = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.dad.id))
    try await f.library.remove(first.id, from: .entity(f.maya.id))
    #expect(FileManager.default.fileExists(atPath: f.library.url(for: first).path))
    try await f.library.remove(first.id, from: .entity(f.dad.id))
    #expect(!FileManager.default.fileExists(atPath: f.library.url(for: first).path))
    #expect(try f.store.photos.photo(id: first.id) == nil)
}

@Test func removingAPhotoThatIsNotOnThePageChangesNothing() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    try await f.library.remove(photo.id, from: .entity(f.dad.id))
    #expect(FileManager.default.fileExists(atPath: f.library.url(for: photo).path))
    #expect(try f.store.photos.photos(of: .entity(f.maya.id)).count == 1)
}

@Test func setCoverMakesAnotherPhotoTheCover() async throws {
    let f = try Fixture()
    let first = try await f.library.add(fileAt: try f.source("a", rgb: 0xE07A2E), assetLocalID: nil, to: .entity(f.maya.id))
    let second = try await f.library.add(fileAt: try f.source("b", rgb: 0x2E7AE0), assetLocalID: nil, to: .entity(f.maya.id))
    try await f.library.setCover(second.id, of: .entity(f.maya.id))
    #expect(try f.store.photos.photos(of: .entity(f.maya.id)).map(\.id) == [second.id, first.id])
}

// MARK: - Sweep

@Test func aFileWithNoRowGoesAtTheSweep() throws {
    let f = try Fixture()
    try Data([1, 2, 3]).write(to: f.photosDir.appending(path: "\(PhotoID().rawValue).jpg"))   // a kill after the file, before the row
    #expect(try PhotoLibrary.sweep(root: f.root, photos: f.store.photos) == .init(rows: 0, files: 1))
    #expect(f.photoFiles.isEmpty)
}

@Test func aPartialFileGoesAtTheSweep() throws {
    let f = try Fixture()
    try Data([1]).write(to: f.photosDir.appending(path: ".\(PhotoID().rawValue).partial"))
    #expect(try PhotoLibrary.sweep(root: f.root, photos: f.store.photos).files == 1)
    #expect(f.photoFiles.isEmpty)
}

@Test func aPhotoWithNoPageGoesAtTheSweep() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    try f.store.entities.delete(f.maya.id)
    #expect(try PhotoLibrary.sweep(root: f.root, photos: f.store.photos) == .init(rows: 1, files: 1))
    #expect(!FileManager.default.fileExists(atPath: f.library.url(for: photo).path))
    #expect(try f.store.photos.photo(id: photo.id) == nil)
}

@Test func deletingASessionLeavesNoPhotoFileAfterTheSweep() async throws {
    let f = try Fixture()   // the tree house is told only in this session
    _ = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .memory(f.treeHouse.id))
    try f.store.sessions.deleteSession(f.session)
    try PhotoLibrary.sweep(root: f.root, photos: f.store.photos)
    #expect(f.photoFiles.isEmpty)
}

@Test func theSweepKeepsAPageWithItsPhoto() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    #expect(try PhotoLibrary.sweep(root: f.root, photos: f.store.photos) == .init(rows: 0, files: 0))
    #expect(f.photoFiles == ["\(photo.id.rawValue).jpg"])
}

@Test func aRowWithAMissingFileStays() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    try FileManager.default.removeItem(at: f.library.url(for: photo))
    #expect(try PhotoLibrary.sweep(root: f.root, photos: f.store.photos) == .init(rows: 0, files: 0))
    #expect(try f.store.photos.photo(id: photo.id) != nil)
}

// MARK: - Location and thumbnails

@Test func photosStayOutOfCloudBackup() throws {
    let f = try Fixture()
    #expect(try PhotoLocation.directory(under: f.root).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    #expect(try PhotoLocation.directory(under: f.root).lastPathComponent == PhotoLocation.directoryName)
}

@Test func thumbnailsAreDownsampled() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(), assetLocalID: nil, to: .entity(f.maya.id))
    let image = try PhotoImport.thumbnail(at: f.library.url(for: photo), maxPixel: 400)
    #expect(max(image.width, image.height) == 400)
}

@Test func aThumbnailIsNotEnlarged() async throws {
    let f = try Fixture()
    let photo = try await f.library.add(fileAt: try f.source(width: 300, height: 200), assetLocalID: nil, to: .entity(f.maya.id))
    let image = try PhotoImport.thumbnail(at: f.library.url(for: photo), maxPixel: 400)
    #expect((image.width, image.height) == (300, 200))
}

// MARK: - Metadata

@Test func metadataReadsSouthAndWestAsNegative() throws {
    let f = try Fixture()
    let meta = try PhotoImport.metadata(of: try f.source(takenAt: "2012:06:14 15:32:10", gps: (-33.9, -70.6)))
    #expect(meta.lat == -33.9 && meta.lon == -70.6 && meta.takenAt?.stored == "2012-06-14T15:32:10")
}

@Test func metadataIgnoresALocationOutOfRange() throws {
    let f = try Fixture()
    let meta = try PhotoImport.metadata(of: try f.source(gps: (95.0, 10.0)))
    #expect(meta.lat == nil && meta.lon == nil, "both or neither")
}

@Test func theHashIsLowerCaseHexOfTheFile() throws {
    let f = try Fixture()
    let file = f.root.appending(path: "abc.txt")
    try Data("abc".utf8).write(to: file)
    #expect(try PhotoImport.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
