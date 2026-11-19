import Testing
@testable import LifelineKit

/// Tiles 88 points wide with 10 between them: one slot is 98 points. Slot i covers [98 i, 98 (i + 1)).
private let stride = 98.0

private struct SlotCase: Sendable, CustomTestStringConvertible {
    let x: Double
    let count: Int
    let slot: Int
    var testDescription: String { "x \(x), \(count) tiles → slot \(slot)" }
}

@Test(arguments: [
    // Three tiles.
    SlotCase(x: 0, count: 3, slot: 0),
    SlotCase(x: 50, count: 3, slot: 0),
    SlotCase(x: 97.9, count: 3, slot: 0),
    SlotCase(x: 98, count: 3, slot: 1),        // the exact boundary belongs to the slot after it
    SlotCase(x: 195.9, count: 3, slot: 1),
    SlotCase(x: 196, count: 3, slot: 2),
    SlotCase(x: 293, count: 3, slot: 2),
    SlotCase(x: 294, count: 3, slot: 2),       // past the last tile: clamped to the last slot
    SlotCase(x: 5000, count: 3, slot: 2),
    SlotCase(x: -0.1, count: 3, slot: 0),      // before the first tile: clamped to the first slot
    SlotCase(x: -250, count: 3, slot: 0),
    // Four tiles.
    SlotCase(x: 0, count: 4, slot: 0),
    SlotCase(x: 196, count: 4, slot: 2),
    SlotCase(x: 293.9, count: 4, slot: 2),
    SlotCase(x: 294, count: 4, slot: 3),
    SlotCase(x: 391.9, count: 4, slot: 3),
    SlotCase(x: 392, count: 4, slot: 3),       // past the last tile
    SlotCase(x: -98, count: 4, slot: 0),
])
private func theSlotUnderTheFinger(_ c: SlotCase) {
    let drag = PhotoShelfDrag(photo: PhotoID(), from: 0, startX: 10, currentX: c.x)
    #expect(drag.target(count: c.count, stride: stride) == c.slot)
}

@Test func anEmptyRowOrNoStrideGivesTheFirstSlot() {
    let drag = PhotoShelfDrag(photo: PhotoID(), from: 0, startX: 10, currentX: 300)
    #expect(drag.target(count: 0, stride: stride) == 0)
    #expect(drag.target(count: 3, stride: 0) == 0)
}

private struct OffsetCase: Sendable, CustomTestStringConvertible {
    let from: Int
    let startX: Double
    let currentX: Double
    let count: Int
    let target: Int
    var testDescription: String { "from \(from), \(startX) → \(currentX), \(count) tiles" }
}

/// The dragged tile is drawn in its target slot plus the offset. That must be where it started plus the finger's
/// movement, so the tile stays under the finger while its target changes.
@Test(arguments: [
    OffsetCase(from: 2, startX: 240, currentX: 240, count: 3, target: 2),   // held, not moved yet
    OffsetCase(from: 2, startX: 240, currentX: 190, count: 3, target: 1),   // crosses into slot 1
    OffsetCase(from: 2, startX: 240, currentX: 40, count: 3, target: 0),    // over the first slot
    OffsetCase(from: 2, startX: 240, currentX: -60, count: 3, target: 0),   // before the first tile: clamped
    OffsetCase(from: 0, startX: 40, currentX: 300, count: 3, target: 2),    // past the last tile: clamped
    OffsetCase(from: 1, startX: 140, currentX: 196, count: 4, target: 2),   // on the boundary
    OffsetCase(from: 3, startX: 330, currentX: 97.9, count: 4, target: 0),  // just before the boundary
    OffsetCase(from: 3, startX: 330, currentX: 98, count: 4, target: 1),    // just after it
])
private func theDraggedTileStaysUnderTheFinger(_ c: OffsetCase) {
    let drag = PhotoShelfDrag(photo: PhotoID(), from: c.from, startX: c.startX, currentX: c.currentX)
    #expect(drag.target(count: c.count, stride: stride) == c.target)
    let offset = drag.offset(count: c.count, stride: stride)
    let drawnAt = Double(c.target) * stride + offset
    let underFinger = Double(c.from) * stride + (c.currentX - c.startX)
    #expect(abs(drawnAt - underFinger) < 1e-9)
}

@Test func theOffsetFollowsTheFingerAcrossATargetChange() {
    // The tile from slot 2 moves left by 1 point across the boundary at 196: its target changes, its place on screen does not jump.
    let before = PhotoShelfDrag(photo: PhotoID(), from: 2, startX: 240, currentX: 196)
    let after = PhotoShelfDrag(photo: PhotoID(), from: 2, startX: 240, currentX: 195)
    #expect(before.target(count: 3, stride: stride) == 2)
    #expect(after.target(count: 3, stride: stride) == 1)
    #expect(before.offset(count: 3, stride: stride) == -44)
    #expect(after.offset(count: 3, stride: stride) == 53)
    let drawnBefore = 2 * stride + before.offset(count: 3, stride: stride)
    let drawnAfter = 1 * stride + after.offset(count: 3, stride: stride)
    #expect(drawnBefore - drawnAfter == 1)
}
