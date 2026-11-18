import Foundation

/// The "When did this happen?" part of the photo card: which state it is in, and its words. The view draws what this says.
public enum PhotoDatePart: Sendable, Equatable {
    public struct Offer: Sendable, Equatable {
        public var text: String
        public var button: String
        public var date: CivilDate
        public var memories: [Memory]
        public var canUndo: Bool
    }

    case hidden
    case offer(Offer)
    case used(text: String, button: String)

    /// `used`: what the taps on this screen changed. `seen`: what those taps settled (`seen(offered:chosen:changed:)`).
    /// A memory that was offered at a tap and is still open (the person left it unchecked) does not bring the offer back.
    /// The counts after a tap come from `used`, so they do not follow the store.
    public static func state(offer: PhotoStoryCard.StoryDateOffer?, holdingCount: Int, used: [PhotoDateChange], seen: Set<MemoryID>) -> PhotoDatePart {
        let open = offer?.memories.filter { !seen.contains($0.id) } ?? []
        if let offer, !open.isEmpty {
            return .offer(Offer(text: "\(sentenceStart(offer.date)) \(countWord(open.count)) \(open.count == 1 ? "moment has" : "moments have") no date you said.",
                                button: openButton(count: open.count, holdingCount: holdingCount), date: offer.date, memories: open,
                                canUndo: !used.isEmpty))
        }
        guard let first = used.first else { return .hidden }
        let count = used.count
        return .used(text: "\(sentenceStart(first.date)) \(countWord(count)) \(count == 1 ? "moment now uses" : "moments now use") that date.",
                     button: count == 1 ? "Used for that one" : "Used for those \(count)")
    }

    /// The memories a tap adds to `seen`: of those `offered` when the control was shown, the ones the write `changed` and
    /// the ones the person left unchecked. A chosen memory the write skipped as stale, and a memory kept after the
    /// control was shown, are not seen: the person never declined them, so the offer comes back for them.
    public static func seen(offered: [Memory], chosen: [Memory], changed: [MemoryID]) -> Set<MemoryID> {
        let written = Set(changed), picked = Set(chosen.map(\.id))
        return Set(offered.map(\.id).filter { written.contains($0) || !picked.contains($0) })
    }

    /// The button of the sheet that lets the person choose moments.
    public static func chooseButton(count: Int) -> String { "Use for \(count)" }

    private static func openButton(count: Int, holdingCount: Int) -> String {
        if count == 1 { return "Use for that one" }
        return count == holdingCount ? "Use for all \(count)" : "Use for those \(count)"
    }

    private static func sentenceStart(_ date: CivilDate) -> String {
        "The photo is dated \(PhotoCaption.longDate(date) ?? "that day")."
    }

    /// "One" to "Twelve", then digits (decision 6 of the plan).
    private static func countWord(_ n: Int) -> String {
        let words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]
        return (1...12).contains(n) ? words[n - 1] : String(n)
    }
}
