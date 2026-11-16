import Foundation

/// What Timeline says about itself now that About lives on You (S3, final review). Pure.
/// Timeline draws moments only; facts, feelings and goals are counted, never drawn.
public enum TimelineSummary {
    /// "N things about your life": visible, told facts, feelings and goals. Hidden ones and stand-ins are
    /// not counted, whatever the tag filter or "Show hidden memories" says: Timeline never shows them, so
    /// the count must not promise them.
    public static func thingsAboutYourLife(_ memories: [Memory]) -> Int {
        memories.filter { !$0.isMoment && !$0.hiddenFromTimeline && !$0.isFloating }.count
    }

    /// "2 memories · 1 chapter · 1999 → now · and 3 things about your life". While a tag filter is on, the
    /// things are left out: the filter applies to moments only, and they are not on this page.
    public static func text(memories: Int, chapters: Int, firstYear: Int?, things: Int, tagFiltered: Bool) -> String {
        var parts = ["\(memories) \(memories == 1 ? "memory" : "memories")"]
        if chapters > 0 { parts.append("\(chapters) \(chapters == 1 ? "chapter" : "chapters")") }
        if let firstYear { parts.append("\(firstYear) → now") }
        if things > 0, !tagFiltered { parts.append("and \(things) \(things == 1 ? "thing" : "things") about your life") }
        return parts.joined(separator: " · ")
    }

    /// The tag menu: the tags that at least one of `moments` carries, once each ignoring case, sorted ignoring
    /// case. A tag only a fact or an entity carries is left out: choosing it would show an empty Timeline.
    public static func menuTags(_ tagsByMemory: [String: [String]], moments: [Memory]) -> [String] {
        var seen = Set<String>()
        let once = moments.filter(\.isMoment).flatMap { tagsByMemory[$0.id.rawValue] ?? [] }.filter { seen.insert($0.lowercased()).inserted }
        return once.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// The filter to keep once the menu is known: a tag no moment carries any more turns off, because the menu
    /// that could clear it may be gone too. Case does not matter.
    public static func filter(_ chosen: String?, offered: [String]) -> String? {
        guard let chosen else { return nil }
        return offered.contains { $0.lowercased() == chosen.lowercased() } ? chosen : nil
    }
}
