import Foundation

/// The files behind the photos: adds a downscaled copy, removes it, and sweeps what a kill leaves behind.
/// Each public method runs as one actor call with no suspension point, so two adds never interleave
/// between the file and the row.
public actor PhotoLibrary {
    private let root: URL
    private let photos: PhotoRepository
    private let directory: URL
    private let writeCopy: @Sendable (_ source: URL, _ destination: URL) throws -> (width: Int, height: Int)

    public init(root: URL, photos: PhotoRepository) {
        self.init(root: root, photos: photos, writeCopy: { try PhotoImport.writeDownscaled(from: $0, to: $1) })
    }

    /// `writeCopy` is the write step; a test makes it fail part way.
    init(root: URL, photos: PhotoRepository, writeCopy: @escaping @Sendable (URL, URL) throws -> (width: Int, height: Int)) {
        self.root = root; self.photos = photos; self.writeCopy = writeCopy
        self.directory = PhotoLocation.path(under: root)
    }

    /// Same photo already stored (decision 7): links it, and writes its file again if that file is missing, so
    /// picking a photo again repairs one that does not show. Otherwise: writes `.<id>.partial`, renames it to
    /// `<id>.jpg`, then inserts the row and link. A kill after the rename leaves a file with no row; the sweep removes it.
    public func add(fileAt source: URL, assetLocalID: String?, to subject: PhotoSubject, now: Date = .now) throws -> Photo {
        try importPhoto(fileAt: source, assetLocalID: assetLocalID, now: now, link: subject)
    }

    /// The import of `add` with no link: the photo waits for a home (a session row that points at it, or a later link).
    /// Same photo already stored: returns it, writes a missing file again, adds no link. A photo that never gets a home
    /// goes at the next sweep.
    public func store(fileAt source: URL, assetLocalID: String?, now: Date = .now) throws -> Photo {
        try importPhoto(fileAt: source, assetLocalID: assetLocalID, now: now, link: nil)
    }

    /// The session lets go of its photo; when nothing else holds the photo, its row and then its file go.
    public func removeFromStory(_ session: SessionID) throws {
        guard let gone = try photos.letGo(of: session) else { return }
        // As in `remove`: a file that will not delete is a file with no row, and the next sweep takes it.
        try? FileManager.default.removeItem(at: directory.appending(path: gone.fileName))
    }

    private func importPhoto(fileAt source: URL, assetLocalID: String?, now: Date, link subject: PhotoSubject?) throws -> Photo {
        let sha256 = try PhotoImport.sha256(of: source)
        if let stored = try photos.photo(sha256: sha256) {
            if !FileManager.default.fileExists(atPath: url(for: stored).path) { _ = try writeFile(from: source, named: stored.fileName) }
            if let subject { try photos.link(stored.id, to: subject) }
            return stored
        }
        let metadata = try PhotoImport.metadata(of: source)
        let id = PhotoID()
        let fileName = Self.fileName(for: id)
        let size = try writeFile(from: source, named: fileName)
        let photo = Photo(id: id, fileName: fileName, assetLocalID: assetLocalID,
                          takenAt: metadata.takenAt, takenOrigin: metadata.takenAt == nil ? nil : .exif,
                          lat: metadata.lat, lon: metadata.lon, locationOrigin: metadata.lat == nil ? nil : .exif,
                          sha256: sha256, pixelWidth: size.width, pixelHeight: size.height, addedAt: now)
        do {
            if let subject { try photos.insert(photo, linkingTo: subject) } else { try photos.insert(photo) }
        } catch {
            try? FileManager.default.removeItem(at: url(for: photo))
            throw error
        }
        return photo
    }

    /// Writes the downscaled copy to `.<name>.partial`, then renames it to `<name>`. A failure leaves no partial file.
    private func writeFile(from source: URL, named fileName: String) throws -> (width: Int, height: Int) {
        let folder = try PhotoLocation.directory(under: root)
        let partial = folder.appending(path: ".\(fileName.dropLast(4)).partial")
        do {
            let size = try writeCopy(source, partial)
            try FileManager.default.moveItem(at: partial, to: folder.appending(path: fileName))
            return size
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Unlinks; when no page is left, deletes the row, then the file.
    public func remove(_ photo: PhotoID, from subject: PhotoSubject) throws {
        guard let gone = try photos.unlink(photo, from: subject) else { return }
        // The row is already gone. A file that will not delete is a file with no row: the next sweep takes it.
        try? FileManager.default.removeItem(at: directory.appending(path: gone.fileName))
    }

    public func setCover(_ photo: PhotoID, of subject: PhotoSubject) throws {
        try photos.setCover(photo, of: subject)
    }

    public nonisolated func url(for photo: Photo) -> URL { directory.appending(path: photo.fileName) }

    public struct Swept: Sendable, Equatable {
        public var rows: Int
        public var files: Int
        public init(rows: Int, files: Int) { self.rows = rows; self.files = files }
    }

    /// The sweep below, as one actor call with no suspension point, so it never runs between an add's file and its row.
    /// Settings runs it before every copy is made (an export, or the safety copy before a restore is staged), so a
    /// photo whose page was deleted in this run does not travel in the copy.
    @discardableResult
    public func sweep() throws -> Swept {
        try Self.sweep(root: root, photos: photos)
    }

    /// Decision 10: unlinked rows and their files; files with no row; `.partial` files. Never a row whose file is missing.
    /// Only `.jpg` and `.partial` names are the library's own; anything else in the folder stays.
    /// It runs at launch, before any `add` can run, and through the actor's `sweep()` before a copy is made. This static
    /// form is not serialised with `add`: a sweep during an add could remove the new file before its row exists, so any
    /// call after launch must go through the actor.
    @discardableResult
    public static func sweep(root: URL, photos: PhotoRepository) throws -> Swept {
        let directory = try PhotoLocation.directory(under: root)
        let orphans = try photos.deleteUnlinked()
        var files = 0
        for orphan in orphans where deleteIfPresent(directory.appending(path: orphan.fileName)) { files += 1 }
        let known = try photos.fileNames()
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where (name.hasSuffix(".jpg") || name.hasSuffix(".partial")) && !known.contains(name) {
            if deleteIfPresent(directory.appending(path: name)) { files += 1 }
        }
        return Swept(rows: orphans.count, files: files)
    }

    private static func fileName(for photo: PhotoID) -> String { "\(photo.rawValue).jpg" }

    /// True when a file was there and is now gone.
    private static func deleteIfPresent(_ file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        return (try? FileManager.default.removeItem(at: file)) != nil
    }
}
