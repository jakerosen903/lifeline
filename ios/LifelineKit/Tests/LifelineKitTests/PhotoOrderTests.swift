import Testing
@testable import LifelineKit

@Test func moving() {
    let a = PhotoID(), b = PhotoID(), c = PhotoID(), x = PhotoID()
    let order = [a, b, c]
    #expect(PhotoOrder.moving(c, to: 0, in: order) == [c, a, b])
    #expect(PhotoOrder.moving(a, to: 2, in: order) == [b, c, a])
    #expect(PhotoOrder.moving(b, to: 0, in: order) == [b, a, c])
    #expect(PhotoOrder.moving(b, to: 1, in: order) == nil)
    #expect(PhotoOrder.moving(a, to: 0, in: order) == nil)
    #expect(PhotoOrder.moving(c, to: 9, in: order) == nil, "clamped to its own place")
    #expect(PhotoOrder.moving(a, to: 9, in: order) == [b, c, a])
    #expect(PhotoOrder.moving(c, to: -3, in: order) == [c, a, b])
    #expect(PhotoOrder.moving(x, to: 0, in: order) == nil)
    #expect(PhotoOrder.moving(a, to: 0, in: [a]) == nil)
    #expect(PhotoOrder.moving(a, to: 0, in: []) == nil)
}
