import Foundation

/// Repairs that earlier versions of the app made necessary. Each one is safe to run again: a
/// second run finds nothing to do. The app runs them once at launch and shows `notice` once.
///
/// Each step is its own write. A step that fails changes nothing and is reported in `failures`; the
/// steps before it stay done, the steps after it still run, and the next launch tries it again.
public enum ArchiveRepair {
    /// One repair, in the order `run` makes them.
    public enum Step: String, Sendable, Equatable {
        case stories, entities, collections, chapters
    }

    /// A step that threw, with the error's text for the log. The text never goes on screen.
    public struct Failure: Sendable, Equatable {
        public var step: Step
        public var message: String
    }

    public struct Report: Sendable, Equatable {
        /// Stories that had the same title and are now one, with how many copies there were.
        public var joinedStories: [StoryRepository.MergedTitle] = []
        /// Places and things that had the same name and are now one ("Ohio." and "Ohio").
        public var joinedEntities: [StoryRepository.MergedTitle] = []
        /// Collections that had the same title and are now one.
        public var joinedCollections: [StoryRepository.MergedTitle] = []
        /// Chapters with no title and no memory. They held nothing, so the notice leaves them out.
        public var removedChapters = 0
        /// Steps that failed. What the other steps joined is still in the report and in `notice`.
        public var failures: [Failure] = []

        /// One sentence for the person, or nil when nothing was joined.
        public var notice: String? {
            let all = joinedStories + joinedEntities + joinedCollections
            switch all.count {
            case 0: return nil
            case 1: return "Joined \(all[0].copies) copies of “\(all[0].title)”."
            default:
                return all.count == joinedStories.count
                    ? "Joined copies of \(all.count) stories that had the same title."
                    : "Joined copies of \(all.count) things that had the same name."
            }
        }
    }

    /// Never throws: a failed step must not hide what the steps before it already changed.
    @discardableResult
    public static func run(_ store: ExtractionStore) -> Report {
        var report = Report()
        /// The step's result, or `fallback` with the failure noted.
        func attempt<T>(_ step: Step, or fallback: T, _ body: () throws -> T) -> T {
            do { return try body() } catch {
                report.failures.append(Failure(step: step, message: "\(error)"))
                return fallback
            }
        }
        let stories = attempt(.stories, or: []) { try store.stories.mergeDuplicateTitles() }
        let entities = attempt(.entities, or: []) { try store.entities.mergeDuplicateTitles() }
        let collections = attempt(.collections, or: []) { try store.chapters.mergeDuplicateCollections() }
        let chapters = attempt(.chapters, or: 0) { try store.chapters.deleteEmptyUntitled() }
        report.joinedStories = stories
        report.joinedEntities = entities
        report.joinedCollections = collections
        report.removedChapters = chapters
        return report
    }
}
