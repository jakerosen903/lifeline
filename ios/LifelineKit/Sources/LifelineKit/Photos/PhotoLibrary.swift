import Foundation

/// The files behind the photos: adds a downscaled copy, removes it, and sweeps what a kill leaves behind.
/// Each public method runs as one actor call with no suspension point, so two adds never interleave
/// between the file and the row.
public actor PhotoLibrary {
    private let root: URL
    private let photos: PhotoRepository
    private let directory: URL

    public init(root: URL, photos: PhotoRepository) {
        self.root = root; self.photos = photos
        self.directory = PhotoLocation.path(under: root)
    }

    /// Same photo already stored (decision 7): links it. Otherwise: writes `.<id>.partial`, renames it to `<id>.jpg`,
    /// then inserts the row and link. A kill after the rename leaves a file with no row; the sweep removes it.
    public func add(fileAt source: URL, assetLocalID: String?, to subject: PhotoSubject, now: Date = .now) throws -> Photo {
        let sha256 = try PhotoImport.sha256(of: source)
        if let stored = try photos.photo(sha256: sha256) {
            try photos.link(stored.id, to: subject)
            return stored
        }
        let metadata = try PhotoImport.metadata(of: source)
        let id = PhotoID()
        let folder = try PhotoLocation.directory(under: root)
        let partial = folder.appending(path: ".\(id.rawValue).partial"), final = folder.appending(path: Self.fileName(for: id))
        let size: (width: Int, height: Int)
        do {
            size = try PhotoImport.writeDownscaled(from: source, to: partial)
            try FileManager.default.moveItem(at: partial, to: final)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        let photo = Photo(id: id, fileName: final.lastPathComponent, assetLocalID: assetLocalID,
                          takenAt: metadata.takenAt, takenOrigin: metadata.takenAt == nil ? nil : .exif,
                          lat: metadata.lat, lon: metadata.lon, locationOrigin: metadata.lat == nil ? nil : .exif,
                          sha256: sha256, pixelWidth: size.width, pixelHeight: size.height, addedAt: now)
        do { try photos.insert(photo, linkingTo: subject) } catch {
            try? FileManager.default.removeItem(at: final)
            throw error
        }
        return photo
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

    /// Decision 10: unlinked rows and their files; files with no row; `.partial` files. Never a row whose file is missing.
    /// Only `.jpg` and `.partial` names are the library's own; anything else in the folder stays.
    @discardableResult
    public static func sweep(root: URL, photos: PhotoRepository) throws -> Swept {
        let directory = try PhotoLocation.directory(under: root)
        let orphans = try photos.deleteUnlinked()
        var files = 0
        for orphan in orphans where remove(directory.appending(path: orphan.fileName)) { files += 1 }
        let known = try photos.fileNames()
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where (name.hasSuffix(".jpg") || name.hasSuffix(".partial")) && !known.contains(name) {
            if remove(directory.appending(path: name)) { files += 1 }
        }
        return Swept(rows: orphans.count, files: files)
    }

    private static func fileName(for photo: PhotoID) -> String { "\(photo.rawValue).jpg" }

    /// True when a file was there and is now gone.
    private static func remove(_ file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        return (try? FileManager.default.removeItem(at: file)) != nil
    }
}
