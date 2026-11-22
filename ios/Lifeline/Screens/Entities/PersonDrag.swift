import CoreTransferable
import LifelineKit
import SwiftUI

/// A face dragged on the People grid (PC-c): the person's id as plain text with a prefix of its own. Plain text needs
/// no type declared in Info.plist; the prefix keeps a drop of any other text (from another app) from meaning a person.
struct PersonDrag: Transferable, Equatable {
    static let prefix = "lifeline-person:"

    let id: PersonID

    init(id: PersonID) { self.id = id }

    /// Nil for any text that is not a dragged face: no prefix, or nothing after it.
    init?(text: String) {
        guard text.hasPrefix(Self.prefix) else { return nil }
        let raw = String(text.dropFirst(Self.prefix.count))
        guard !raw.isEmpty else { return nil }
        id = PersonID(rawValue: raw)
    }

    var text: String { Self.prefix + id.rawValue }

    static var transferRepresentation: some TransferRepresentation {
        // A refused import gives the drop no item, so the drop does nothing.
        ProxyRepresentation(exporting: \.text) { text in
            guard let drag = PersonDrag(text: text) else { throw NotAPerson() }
            return drag
        }
    }

    private struct NotAPerson: Error {}
}

extension View {
    /// A tile that can be dragged onto another and take a drop. `onDrop` gets the dragged person; `isTargeted` is
    /// true while a drag is over this tile. The drag starts after the system's long press, so a tap still opens the page.
    func personDragAndDrop(_ person: PersonID, onDrop: @escaping (PersonID) -> Bool,
                           isTargeted: @escaping (Bool) -> Void) -> some View {
        draggable(PersonDrag(id: person))
            .dropDestination(for: PersonDrag.self) { items, _ in
                // A drop of a tile on itself, or of text that is not a face, does nothing.
                guard let dragged = items.first, dragged.id != person else { return false }
                return onDrop(dragged.id)
            } isTargeted: { isTargeted($0) }
    }
}
