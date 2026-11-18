import LifelineKit
import SwiftUI

/// "Photos" (decision 13): every photo the subject holds, key photo first, as small square buttons in one scrolling
/// line. The first photo is the key photo and carries the pill "Key photo". A tap opens the viewer. With two or more
/// photos a line says how to change the key photo, and a long press then a drag moves a tile: the others make room
/// where it will land, and on release the row reports the index under the finger. With VoiceOver, every tile but
/// the first has "Move to front". The heading sits in the row, as "Tags" does.
struct PhotoRow: View {
    let photos: [PlacedPhoto]
    let label: String
    let cache: PhotoImageCache
    let onOpen: (PlacedPhoto) -> Void
    /// The photo and the index where the drag ended. The shelf asks the kit for the order; a move to the same place writes nothing.
    let onMove: (PhotoID, Int) -> Void

    @GestureState private var drag: PhotoRowDrag?
    /// True from the moment a press is held until it ends or is cancelled: a gesture state resets on both.
    @GestureState private var isHolding = false
    /// One shot: set when a press is held, used up by the button's action. The button can fire on the release of a
    /// hold, and that release is not a tap. It is cleared one run-loop turn after the hold ends, so it never eats a
    /// later tap, whether the button's action runs before or after the gesture's end on that release.
    @State private var holdEndsTap = false

    private static let side: CGFloat = 88
    private static let spacing: CGFloat = 10
    private static let stride = side + spacing
    private static let space = "photoRow"

    /// One photo is already the key photo: nothing to move.
    private var canMove: Bool { photos.count >= 2 }

    /// The row as it is drawn: during a drag, the order the drop would store.
    private var shown: [PlacedPhoto] {
        guard let drag else { return photos }
        let ids = photos.map(\.id)
        guard let order = PhotoOrder.moving(drag.photo, to: drag.target(count: photos.count, stride: Self.stride), in: ids) else { return photos }
        return order.compactMap { id in photos.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos").sectionHeadingStyle()
            if canMove {
                Text("The first photo is the key photo. Hold a photo and drag it to the front to change it.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.shelfHint")
            }
            ScrollView(.horizontal) {
                HStack(spacing: Self.spacing) {
                    let order = shown
                    ForEach(Array(order.enumerated()), id: \.element.id) { index, placed in
                        // `from` is the stored place: it must not follow the tile while the others make room.
                        tile(placed, isFirst: index == 0, from: photos.firstIndex(of: placed) ?? index)
                    }
                }
                .coordinateSpace(.named(Self.space))
                .animation(.snappy, value: shown.map(\.id))
            }
            .scrollIndicators(.hidden)
            // A held tile follows the finger; the row must not scroll under it.
            .scrollDisabled(drag != nil)
        }
        .onChange(of: isHolding) { _, held in
            if !held { DispatchQueue.main.async { holdEndsTap = false } }
        }
    }

    private func tile(_ placed: PlacedPhoto, isFirst: Bool, from: Int) -> some View {
        let isDragged = drag?.photo == placed.id
        return ZStack(alignment: .topLeading) {
            thumb(placed, isFirst: isFirst)
            if isFirst { keyLabel }
        }
        .scaleEffect(isDragged ? 1.06 : 1)
        .shadow(color: Theme.ink.opacity(isDragged ? 0.25 : 0), radius: 8, y: 4)
        .offset(x: isDragged ? drag?.offset(count: photos.count, stride: Self.stride) ?? 0 : 0)
        .zIndex(isDragged ? 1 : 0)
        // Simultaneous, so a quick tap still reaches the button; a high-priority gesture swallowed it. A plain swipe
        // moves the finger before the press is held, the press fails and the row scrolls.
        .simultaneousGesture(moveGesture(placed.id, from: from), including: canMove ? .all : .subviews)
    }

    private func thumb(_ placed: PlacedPhoto, isFirst: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return Button {
            if holdEndsTap { holdEndsTap = false; return }
            onOpen(placed)
        } label: {
            PhotoImageView(photo: placed.photo, size: .small, cache: cache) { Theme.sand }
                .frame(width: Self.side, height: Self.side)
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(PhotoCaption.taken(placed.photo.takenAt) ?? "")
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            if canMove, !isFirst {
                Button("Move to front") { onMove(placed.id, 0) }
            }
        }
        .accessibilityIdentifier("photo.thumb")
    }

    /// Decision 11: a small pill with its own fill, so it reads on any photo. Its own element, read next to the tile.
    private var keyLabel: some View {
        Text("Key photo")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            // The pill must stay on an 88-point tile; past this size it would cover the photo.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.linen))
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityIdentifier("photo.keyLabel")
    }

    private func moveGesture(_ photo: PhotoID, from: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($drag) { value, state, _ in
                guard case .second(true, let moved?) = value else { return }
                if state == nil { state = PhotoRowDrag(photo: photo, from: from, startX: moved.startLocation.x, currentX: moved.location.x) }
                state?.currentX = moved.location.x
            }
            .updating($isHolding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                if case .second(true, _) = value, !holdEndsTap { holdEndsTap = true }
            }
            .onEnded { value in
                guard case .second(true, let moved?) = value else { return }
                let end = PhotoRowDrag(photo: photo, from: from, startX: moved.startLocation.x, currentX: moved.location.x)
                onMove(photo, end.target(count: photos.count, stride: Self.stride))
            }
    }
}
