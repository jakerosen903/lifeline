import Foundation

/// What the app may read of the photo library. The app maps the system's answer to this; the kit never imports Photos.
public enum PhotoAccess: Sendable, Equatable {
    /// The system has not asked yet.
    case notAsked
    /// Every photo: the app shows the Favorites album.
    case full
    /// Only the photos the person allowed.
    case limited
    /// Refused or restricted. The system picker still works, with no permission.
    case none
}

/// The first screen of "Tell a story about a photo". The explanation shows only while the system has not asked,
/// so there is no stored "explained" flag: the system's status is the one record.
public enum PhotoStoryStart: Sendable, Equatable {
    /// The app's explanation, then the system prompt.
    case explain
    /// The grid of photos the app may show, under this heading.
    case grid(heading: String)
    /// The system picker, which needs no permission: no access, or nothing to show. No error, no second ask.
    case picker

    public static func route(access: PhotoAccess, photoCount: Int) -> PhotoStoryStart {
        switch access {
        case .notAsked: .explain
        case .full where photoCount > 0: .grid(heading: "Your favorites")
        case .limited where photoCount > 0: .grid(heading: "Photos you allowed")
        case .full, .limited, .none: .picker
        }
    }
}
