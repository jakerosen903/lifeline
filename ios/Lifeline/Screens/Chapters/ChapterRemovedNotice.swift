import SwiftUI

/// "Removed “{name}”." with Undo, in the slot You uses for its notice. It reads the Timeline's view
/// model, which owns the receipt and its time, so the notice outlives the sheet that removed the chapter.
/// The Timeline shows it, and so does the life map on its bottom edge. When Undo fails, the notice
/// shows the failure in its own place, with Undo to try again: the Timeline's error line can be
/// under the life map.
struct ChapterRemovedNotice: View {
    let timeline: TimelineViewModel
    /// After Undo, for a page that must read the store again (the life map).
    var onUndone: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let text = timeline.removedChapterNotice {
                NoticeSlot(text: timeline.undoChapterFailure ?? text, isError: timeline.undoChapterFailure != nil, identifier: "chapter.removed") {
                    Button("Undo") { if timeline.undoRemoveChapter() { onUndone() } }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Theme.oliveOnFill)
                        .accessibilityIdentifier("chapter.undo")
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        // Under Reduce Motion the notice appears and leaves without animation.
        .animation(reduceMotion ? nil : .default, value: timeline.removedChapterNotice)
    }
}
