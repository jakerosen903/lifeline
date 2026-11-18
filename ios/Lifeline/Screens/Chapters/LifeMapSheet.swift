import LifelineKit
import SwiftUI

/// "Chapters": every chapter the person has named, as bars on one year axis, and under them the
/// chapters not placed in time yet. A tap on a row or a name opens the chapter's sheet; the map stays
/// open under it and reads the store again when it closes.
struct LifeMapSheet: View {
    let viewModel: LifeMapViewModel
    /// For the removal notice and its Undo, which the Timeline owns.
    let timeline: TimelineViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var openChapter: ChapterSheetViewModel?
    @State private var sayWhenTarget: LifeMap.Unplaced?

    static let emptyText = "A chapter is a name you gave to a stretch of your life."
    static let firstLine = "Every stretch of your life you have named. Tap one to see its moments."

    var body: some View {
        NavigationStack {
            // One vertical scroll: thirty chapters, or the largest text, still reach the last row.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let map = viewModel.map { content(map) }
                    if let error = viewModel.error { ErrorLine(text: error).font(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .accessibilityIdentifier("lifemap.sheet")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChapterRemovedNotice(timeline: timeline) { viewModel.reload() }
            }
            .linenBackground()
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("lifemap.done")
                }
            }
        }
        .sheet(item: $openChapter, onDismiss: { viewModel.reload() }) { ChapterSheet(viewModel: $0) }
        .sheet(item: $sayWhenTarget, onDismiss: { viewModel.reload() }) { chapter in
            TellMeWhenSheet(title: chapter.title, birthDate: viewModel.birthDate, heading: "From when to when?") { viewModel.sayWhen(chapter.id, $0) }
        }
    }

    /// With no chapter, only the sentence: no periods, no axis, no header.
    @ViewBuilder
    private func content(_ map: LifeMap) -> some View {
        if map.isEmpty {
            Text(Self.emptyText)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lifemap.empty")
        } else {
            Text(Self.firstLine)
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !map.rows.isEmpty { chart(map) }
            if !map.unplaced.isEmpty { unplaced(map.unplaced) }
        }
    }

    private func chart(_ map: LifeMap) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LifeMapPeriodNames(map: map)
            VStack(spacing: 0) {
                ForEach(map.rows) { row in
                    LifeMapRow(row: row, label: map.summary(of: row)) {
                        openChapter = viewModel.chapterSheet(for: row.id)
                    }
                }
            }
            .background { LifeMapPeriodColumns(map: map) }
            LifeMapYears(map: map)
        }
    }

    private func unplaced(_ chapters: [LifeMap.Unplaced]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not placed in time yet").sectionHeadingStyle()
            // At accessibility sizes "Say when" goes under the name, so the name keeps the width.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 12))
            ForEach(chapters) { chapter in
                layout {
                    Button { openChapter = viewModel.chapterSheet(for: chapter.id) } label: {
                        Text(chapter.title)
                            .font(.system(.body, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The name alone would not say why it is here; VoiceOver reads that it has no dates.
                    .accessibilityLabel("\(chapter.title), no dates yet")
                    Button("Say when") { sayWhenTarget = chapter }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.oliveText)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Say when: \(chapter.title)")
                        .accessibilityIdentifier("lifemap.sayWhen")
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lifemap.unplaced")
    }
}
