import Foundation

/// One line on the You page: something the person said, or an idea of theirs (S3). Pure.
public struct PortraitLine: Sendable, Equatable, Identifiable {
    public enum Part: Sendable, Equatable { case whoYouAre, howItFelt, whatYouThink, hopingFor }
    public enum Source: Sendable, Equatable { case memory(Memory), idea(Entity) }

    public var source: Source
    public var part: Part
    /// The person's own words, cleaned, or the title that stands in for them.
    public var text: String
    /// True only for the person's own words, which are drawn in quotation marks. A title is not.
    public var isOwnWords: Bool
    /// Facts only.
    public var tags: [String]
    /// Feelings only: what the feeling is about, from a link the person's words made. Never guessed.
    public var about: Entity?
    /// Nil: there is no recording to play, so no play control.
    public var telling: Telling?

    public var id: String {
        switch source {
        case .memory(let memory): "memory:\(memory.id.rawValue)"
        case .idea(let entity): "idea:\(entity.id.rawValue)"
        }
    }
}

/// What the You page shows: the header, the strip and four parts, and which line leads (S3).
/// Nothing is guessed or filled in: a part with no line is empty, a date nobody gave is absent.
public struct Portrait: Sendable, Equatable {
    public var owner: Entity?
    public var name: String?
    public var birthLine: String?
    /// Nil with no owner or no owner moment.
    public var strip: LifeStrip?
    public var whoYouAre: [PortraitLine]
    public var howItFelt: [PortraitLine]
    public var whatYouThink: [PortraitLine]
    public var hopingFor: [PortraitLine]

    /// Lines that can lead: the person's own words and a recording to play, in part order.
    public var leadPool: [PortraitLine] {
        (whoYouAre + howItFelt + hopingFor).filter { $0.isOwnWords && $0.telling != nil }
    }

    public var isEmpty: Bool { whoYouAre.isEmpty && howItFelt.isEmpty && whatYouThink.isEmpty && hopingFor.isEmpty }

    public init(_ source: PortraitSource, currentYear: Int) {
        owner = source.owner
        let typedName = source.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerName = source.owner?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        name = [typedName, ownerName].lazy.compactMap { $0 }.first { !$0.isEmpty }
        birthLine = Self.birthLine(birthYear: source.birth?.year, place: source.profile?.birthPlaceText)
        let moments = EntityPage.sections(details: [], mentions: source.ownerMoments).moments.map(\.range)
        let made = source.owner == nil ? nil : LifeStrip(moments: moments, birthYear: source.birth?.year, currentYear: currentYear)
        strip = made?.sentence == nil ? nil : made

        let ownerID = source.owner?.id
        let told = source.aboutMemories
            .filter { !$0.hiddenFromTimeline && !$0.isFloating }
            .sorted { Self.oldestTold($0, $1, source.memoryTellings) }

        func line(_ memory: Memory, _ part: PortraitLine.Part) -> PortraitLine {
            let own = EntityPage.ownWordsQuote(of: memory)
            let links = source.links[memory.id] ?? []
            // What a feeling is about: the first other person, place or thing it describes, else the first it names.
            let others = links.filter { $0.entity.id != ownerID && $0.entity.type != .idea && !$0.entity.hiddenFromTimeline }
            let about = part == .howItFelt ? (others.first { $0.relation == .detail } ?? others.first)?.entity : nil
            return PortraitLine(source: .memory(memory), part: part, text: own ?? memory.title, isOwnWords: own != nil,
                                tags: part == .whoYouAre ? source.memoryTags[memory.id.rawValue] ?? [] : [],
                                about: about, telling: source.memoryTellings[memory.id])
        }

        // Decision 2: a fact about you, or about nobody. A detail link only to someone else sends it to their page;
        // a hidden entity is someone else too (the person hid it, the fact follows it).
        whoYouAre = told.filter { $0.kind == .fact }.filter { memory in
            let details = (source.links[memory.id] ?? []).filter { $0.relation == .detail }
            return details.isEmpty || details.contains { $0.entity.id == ownerID }
        }.map { line($0, .whoYouAre) }
        howItFelt = told.filter { $0.kind == .feeling }.map { line($0, .howItFelt) }
        hopingFor = told.filter { $0.kind == .goal }.map { line($0, .hopingFor) }
        // An idea's title is the person's words or a dated default; either way it is not drawn as a quote.
        whatYouThink = source.ideas.filter { !$0.hiddenFromTimeline }.map {
            PortraitLine(source: .idea($0), part: .whatYouThink, text: $0.title, isOwnWords: false, tags: [], about: nil, telling: source.ideaTellings[$0.id])
        }
    }

    /// Decision 7: by when it was told, then the span's start, then id. No recording sorts after, by id.
    private static func oldestTold(_ a: Memory, _ b: Memory, _ tellings: [MemoryID: Telling]) -> Bool {
        switch (tellings[a.id], tellings[b.id]) {
        case let (x?, y?): return (x.toldAt, x.range.start, a.id.rawValue) < (y.toldAt, y.range.start, b.id.rawValue)
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.id.rawValue < b.id.rawValue
        }
    }

    // MARK: - Copy

    /// Only what was typed: "born 1990 in Dayton", "born 1990", "born in Dayton", or nothing.
    public static func birthLine(birthYear: Int?, place: String?) -> String? {
        let place = place?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch (birthYear, place) {
        case let (year?, place?): return "born \(year) in \(place)"
        case let (year?, nil): return "born \(year)"
        case let (nil, place?): return "born in \(place)"
        case (nil, nil): return nil
        }
    }

    /// "said in October", or "said in October 2025" when the year is not this one. Session start, so known, not guessed.
    public static func saidWhen(_ toldAt: Date, now: Date, calendar: Calendar = .current) -> String {
        // The copy is English with Gregorian years: only the time zone comes from the device's calendar.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.timeZone = gregorian.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = gregorian.component(.year, from: toldAt) == gregorian.component(.year, from: now) ? "MMMM" : "MMMM yyyy"
        return "said in \(formatter.string(from: toldAt))"
    }

    // MARK: - The lead and the chips

    /// The kept line while it is still in the pool; else `pick(leadPool.count)`; nil for an empty pool, without calling `pick`.
    public func lead(keeping kept: PortraitLine.ID?, pick: (Int) -> Int) -> PortraitLine? {
        let pool = leadPool
        if let kept, let line = pool.first(where: { $0.id == kept }) { return line }
        guard !pool.isEmpty else { return nil }
        return pool[min(max(pick(pool.count), 0), pool.count - 1)]
    }

    /// The tags on `whoYouAre` (without the lead) once each, ignoring case, sorted ignoring case.
    public func tags(leaving lead: PortraitLine.ID?) -> [String] {
        var seen = Set<String>()
        let once = whoYouAre.filter { $0.id != lead }.flatMap(\.tags).filter { seen.insert($0.lowercased()).inserted }
        return once.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// The part's lines without the lead. For `.whoYouAre`, only those carrying `tag` while it is still among `tags(leaving:)`;
    /// a tag that is gone shows everything.
    public func lines(_ part: PortraitLine.Part, leaving lead: PortraitLine.ID?, tag: String?) -> [PortraitLine] {
        let all: [PortraitLine] = switch part {
        case .whoYouAre: whoYouAre
        case .howItFelt: howItFelt
        case .whatYouThink: whatYouThink
        case .hopingFor: hopingFor
        }
        let rest = all.filter { $0.id != lead }
        guard part == .whoYouAre, let tag = tag?.lowercased(), tags(leaving: lead).contains(where: { $0.lowercased() == tag }) else { return rest }
        return rest.filter { $0.tags.contains { $0.lowercased() == tag } }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
