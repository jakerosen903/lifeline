import LifelineKit
import UIKit

/// One photo in the person's library that the app may show: the asset's local identifier, nothing else.
struct LibraryPhoto: Identifiable, Sendable, Equatable {
    let id: String
}

/// The photo library as "Tell a story about a photo" sees it (plan decision 9). The live source is PhotoKit; under
/// `-uiTesting` a scripted source serves generated photos. Only the entry's screens use it: "Add a photo" keeps the
/// system picker and never reads the access.
protocol PhotoPickSource: Sendable {
    /// The current access, without asking.
    func access() -> PhotoAccess
    /// Shows the system prompt when the system has not asked yet; otherwise returns the current access.
    func requestAccess() async -> PhotoAccess
    /// Favorites (full access) or the allowed set (limited), newest first. Empty without access.
    func photos() async -> [LibraryPhoto]
    /// A decoded image that fills a square of `side` pixels, for the grid. Nil when the photo cannot be read.
    func thumbnail(for photo: LibraryPhoto, side: CGFloat) async -> UIImage?
    /// A temporary copy of the original, for `PhotoLibrary.store`. The caller removes it.
    func file(for photo: LibraryPhoto) async throws -> URL
}
