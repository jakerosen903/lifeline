import Testing
@testable import LifelineKit

@Test func textColoursPassOnEverySurface() {
    for surface in [Palette.linen, Palette.sand, Palette.card] {
        #expect(Palette.contrast(Palette.ink, surface) >= 4.5)
        #expect(Palette.contrast(Palette.secondaryText, surface) >= 4.5)
        #expect(Palette.contrast(Palette.ochreText, surface) >= 4.5)
        #expect(Palette.contrast(Palette.oliveText, surface) >= 4.5)
    }
    #expect(Palette.contrast(0xFFFFFF, Palette.olive) >= 4.5)
}

@Test func stoneIsNotATextColour() {
    #expect(Palette.contrast(Palette.stone, Palette.linen) < 4.5)
}

@Test func contrastMatchesWCAGReferenceValues() {
    #expect(Palette.contrast(0x000000, 0xFFFFFF) == 21)
    #expect(Palette.contrast(0xFFFFFF, 0xFFFFFF) == 1)
    #expect(Palette.contrast(0x000000, 0xFFFFFF) == Palette.contrast(0xFFFFFF, 0x000000))
}
