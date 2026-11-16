/// The five sections at the root of the app, in tab-bar order.
enum AppTab: Hashable, CaseIterable {
    case timeline, people, places, things, you

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .people: "People"
        case .places: "Places"
        case .things: "Things"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: "text.book.closed"
        case .people: "person.2"
        case .places: "map"
        case .things: "shippingbox"
        case .you: "person.crop.circle"
        }
    }

    var accessibilityIdentifier: String { "tab.\(self)" }
}
