import Foundation
import Synchronization

/// Deterministic replies for UI tests and demos: a reflection of the newest segment's last four words.
/// The segment index is the count of `reply` calls so far, from 0; indexes in `disclosureOn` flag a past disclosure.
public final class ScriptedInterviewerService: InterviewerService {
    private let disclosureOn: Set<Int>
    private let calls = Mutex(0)

    public init(disclosureOn: Set<Int> = []) { self.disclosureOn = disclosureOn }

    public func reply(to request: InterviewerRequest) async throws(ExtractionError) -> InterviewerReply {
        let index = calls.withLock { n in defer { n += 1 }; return n }
        let disclosure: DisclosureKind = disclosureOn.contains(index) ? .past : .none
        guard let newest = request.segments.first else {
            return InterviewerReply(kind: .none, text: nil, askedAboutApp: false, disclosure: disclosure, wantsToStop: false)
        }
        let words = newest.split(whereSeparator: \.isWhitespace).suffix(4).joined(separator: " ")
        let text = words.prefix(1).uppercased() + words.dropFirst()
        return InterviewerReply(kind: .reflection, text: text, askedAboutApp: false, disclosure: disclosure, wantsToStop: false)
    }
}
