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

    /// Sessions with a heavy moment, from the source.
    public var heavySessions: Set<SessionID>

    /// Lines that can lead: the person's own words and a recording to play, in part order. A line first told in
    /// a heavy session (a disclosure, a wish to stop) never leads: it is not put at title size with a play button
    /// on a tab switch. It still shows in its part, with its play control (PRINCIPLES, session arc and safety).
    public var leadPool: [PortraitLine] {
        (whoYouAre + howItFelt + hopingFor).filter { line in
            guard line.isOwnWords, let telling = line.telling else { return false }
            return !heavySessions.contains(telling.sessionID)
        }
    }

    public var isEmpty: Bool { whoYouAre.isEmpty && howItFelt.isEmpty && whatYouThink.isEmpty && hopingFor.isEmpty }

    public init(_ source: PortraitSource, currentYear: Int) {
        owner = source.owner
        heavySessions = source.heavySessions
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
        let sameYear = gregorian.component(.year, from: toldAt) == gregorian.component(.year, from: now)
        return "said in \(MonthFormatters.shared.string(from: toldAt, timeZone: gregorian.timeZone, withYear: !sameYear))"
    }

    /// A length in words for VoiceOver, with the same whole seconds as the visible "m:ss":
    /// "4 seconds", "1 minute", "1 minute 5 seconds", "1 hour 2 minutes 5 seconds". Never negative.
    public static func spokenDuration(ms: Int) -> String {
        let total = max(0, ms) / 1_000
        let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var parts: [String] = []
        if h > 0 { parts.append(unit(h, "hour")) }
        if m > 0 { parts.append(unit(m, "minute")) }
        if s > 0 || parts.isEmpty { parts.append(unit(s, "second")) }
        return parts.joined(separator: " ")
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

/// "October" and "October 2025" formatters, made once per time zone instead of once per goal row per body pass.
/// `DateFormatter` is not `Sendable`; every use happens under the lock, so the cache is safe from any thread.
private final class MonthFormatters: @unchecked Sendable {
    static let shared = MonthFormatters()
    private let lock = NSLock()
    private var cache: [String: DateFormatter] = [:]

    func string(from date: Date, timeZone: TimeZone, withYear: Bool) -> String {
        lock.withLock {
            let key = "\(timeZone.identifier)|\(withYear)"
            let formatter = cache[key] ?? {
                var gregorian = Calendar(identifier: .gregorian)
                gregorian.timeZone = timeZone
                let made = DateFormatter()
                made.calendar = gregorian
                made.timeZone = timeZone
                made.locale = Locale(identifier: "en_GB")
                made.dateFormat = withYear ? "MMMM yyyy" : "MMMM"
                cache[key] = made
                return made
            }()
            return formatter.string(from: date)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
