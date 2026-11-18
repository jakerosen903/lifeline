import LifelineKit
import SwiftUI

/// One chapter: its name, the years the person said ("No dates yet" until then), and the moments
/// they filed in it. "Rename", "Say when it was" and "Remove chapter…". A removal never removes a
/// memory, and the sheet says so under the buttons.
struct ChapterSheet: View {
    let viewModel: ChapterSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    /// Kept after a refused rename, so the alert opens again with what the person typed.
    @State private var renameText = ""
    @State private var sayingWhen = false
    @State private var confirmingRemove = false

    private var canSave: Bool { !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            // A List, so at the largest text size the members and the buttons scroll.
            List {
                header
                if !viewModel.members.isEmpty { membersSection }
                buttonsSection
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .accessibilityIdentifier("chapter.sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("chapter.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: viewModel.isGone) { _, gone in if gone { dismiss() } }
        .alert("Rename", isPresented: $renaming) {
            TextField("Chapter name", text: $renameText)
                .accessibilityIdentifier("chapter.renameField")
            Button("Save") { if viewModel.rename(to: renameText) { renameText = "" } }
                .disabled(!canSave)
                .accessibilityIdentifier("chapter.renameSave")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.renameTaken ? Self.takenText : "In your own words.")
        }
        .confirmationDialog("Remove “\(viewModel.nameInNotice)”?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove chapter", role: .destructive) { viewModel.remove() }
                .accessibilityIdentifier("chapter.confirmRemove")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.removeText)
        }
        .sheet(isPresented: $sayingWhen) {
            TellMeWhenSheet(title: viewModel.title, birthDate: viewModel.birthDate, heading: "From when to when?") { viewModel.sayWhen($0) }
        }
    }

    static let takenText = "You already have a chapter with this name."
    static let removeText = "Removing a chapter never removes a memory. Its moments stay on your timeline."

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                // One line: a long name truncates rather than pushing the years and buttons down.
                Text(viewModel.title)
                    .font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(1).truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("chapter.name")
                Text(viewModel.yearsText)
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("chapter.years")
                if viewModel.renameTaken {
                    Text(Self.takenText)
                        .font(.footnote).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chapter.renameTaken")
                }
                if let error = viewModel.error { ErrorLine(text: error).font(.footnote) }
            }
            .listRowBackground(Color.clear)
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(viewModel.members) { member in
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.title).foregroundStyle(Theme.ink)
                    Text(member.dateText).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(member.title)
                .accessibilityValue(member.dateText)
                .accessibilityIdentifier("chapter.member")
            }
        }
        .listRowBackground(Theme.card)
    }

    private var buttonsSection: some View {
        Section {
            Button("Rename", systemImage: "pencil") { renameText = viewModel.renameTaken ? renameText : (viewModel.name ?? ""); renaming = true }
                .accessibilityIdentifier("chapter.rename")
            Button("Say when it was", systemImage: "calendar") { sayingWhen = true }
                .accessibilityIdentifier("chapter.sayWhen")
            Button("Remove chapter…", systemImage: "bookmark.slash", role: .destructive) { confirmingRemove = true }
                .accessibilityIdentifier("chapter.remove")
        } footer: {
            Text(Self.removeText).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .tint(Theme.oliveText)
        .listRowBackground(Theme.card)
    }
}
