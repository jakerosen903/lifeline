import Foundation

/// How a memory came to be linked to a person. A link made before v15 has no origin (nil).
/// `assumed` is a guess the app made and the owner has not seen; `said` is the owner's own
/// words matched to a person; `confirmed` is the owner's action; `new` is a person the
/// app created for a name nobody matched.
public enum LinkOrigin: String, Codable, Sendable, CaseIterable {
    case assumed, said, confirmed, new

    /// How much the owner stands behind the link. Only the owner's action reaches the top.
    public var strength: Int {
        switch self {
        case .confirmed: 3
        case .said: 2
        case .assumed: 1
        case .new: 0
        }
    }

    /// The stronger of two origins. A missing origin is weaker than every case.
    public static func stronger(_ a: LinkOrigin?, _ b: LinkOrigin?) -> LinkOrigin? {
        switch (a, b) {
        case (nil, nil): nil
        case (let only?, nil), (nil, let only?): only
        case (let x?, let y?): x.strength >= y.strength ? x : y
        }
    }
}

/// Where a person's name came from.
public enum NameOrigin: String, Codable, Sendable {
    case said, typed, contact
}
