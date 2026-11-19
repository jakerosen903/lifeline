import Foundation

/// The store step of "Tell a story about a photo", which the person can cancel while the photo is copied (an iCloud
/// download can take a while). A cancel is checked after the copy and before the store, so a cancelled pick stores
/// nothing. Nothing is deleted after a store: `PhotoLibrary.store` keeps one copy per photo, so the row it returns
/// may already belong to a page.
public enum CancellablePhotoStore {
    /// Copies with `fetch`, then stores the copy unless `isCancelled`. The copy goes either way. Nil: cancelled.
    public static func fetchAndStore(fetch: () async throws -> URL, assetLocalID: String?, into library: PhotoLibrary,
                                     isCancelled: () -> Bool, isolation: isolated (any Actor)? = #isolation) async throws -> Photo? {
        let file = try await fetch()
        defer { try? FileManager.default.removeItem(at: file) }
        return try await store(fileAt: file, assetLocalID: assetLocalID, into: library, isCancelled: isCancelled)
    }

    /// Stores `file` unless `isCancelled`. The file belongs to the caller (the picker path removes its own copy). Nil: cancelled.
    public static func store(fileAt file: URL, assetLocalID: String?, into library: PhotoLibrary,
                             isCancelled: () -> Bool, isolation: isolated (any Actor)? = #isolation) async throws -> Photo? {
        guard !isCancelled() else { return nil }
        return try await library.store(fileAt: file, assetLocalID: assetLocalID)
    }
}
