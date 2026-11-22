import LifelineKit
import SwiftUI

/// "Same as another person…" as one sheet. With `picker` the list of the other people shows first; a tap runs the
/// check and pushes the confirm, or closes the sheet when the check refused (the host shows why). Without `picker` the
/// sheet opens on the confirm of the pair the model already checked. Nothing changes before "Merge".
struct PersonMergeSheet: View {
    let viewModel: PersonMergeViewModel
    /// The person that goes: the page's person. Nil only when the sheet opens on the confirm.
    let leaving: Person?
    let picker: Bool
    let onMerged: (PersonMergeReceipt) -> Void

    init(viewModel: PersonMergeViewModel, leaving: Person?, picker: Bool, onMerged: @escaping (PersonMergeReceipt) -> Void) {
        self.viewModel = viewModel
        self.leaving = leaving
        self.picker = picker
        self.onMerged = onMerged
    }

    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Group {
                if picker { pickerList } else { confirm }
            }
            .navigationDestination(isPresented: $confirming) { confirm }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - The picker

    private var pickerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // With no person that goes, a tap closes the sheet (`pick`), so the title is left out, not shown with no name.
                if let leaving {
                    Text("Who is \(leaving.displayName) the same as?")
                        .font(.system(.title2, design: .serif).weight(.medium)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if viewModel.others.isEmpty {
                    Text("No other people yet.").font(.body).foregroundStyle(Theme.secondaryText)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.others) { personRow($0) }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merge.picker")
        .linenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func personRow(_ person: Person) -> some View {
        Button { pick(person) } label: {
            HStack(spacing: 12) {
                PersonFace(id: EntityID(rawValue: person.id.rawValue), name: person.displayName,
                           cover: viewModel.cover(of: person.id), cache: viewModel.photoImages, size: 40)
                Text(person.displayName).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.displayName)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("merge.picker.person")
    }

    /// The picked person stays (plan decision 2). A refused pair, or no person that goes, closes the sheet; the host
    /// says why.
    private func pick(_ staying: Person) {
        guard let leaving else { viewModel.leavingIsGone(); dismiss(); return }
        viewModel.ask(leaving.id, into: staying.id)
        if viewModel.preview != nil { confirming = true } else { dismiss() }
    }

    // MARK: - The confirm

    @ViewBuilder private var confirm: some View {
        if let preview = viewModel.preview {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Same person?")
                        .font(.system(.title2, design: .serif).weight(.medium)).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    faces(preview)
                    lines(preview)
                    buttons
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("merge.confirm")
            .linenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The one that goes, an arrow, the one that stays. At accessibility text sizes they stack.
    private func faces(_ preview: PersonMergePreview) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            face(preview.leaving)
            Image(systemName: stacked ? "arrow.down" : "arrow.right")
                .font(.title2).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            face(preview.staying)
        }
        .frame(maxWidth: .infinity)
    }

    /// The picture reads as the name; the name under it is the same words, so VoiceOver skips it.
    private func face(_ person: Person) -> some View {
        VStack(spacing: 8) {
            ZStack {
                PersonFace(id: EntityID(rawValue: person.id.rawValue), name: person.displayName,
                           cover: viewModel.cover(of: person.id), cache: viewModel.photoImages, size: 64)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(person.displayName)
            .accessibilityAddTraits(.isImage)
            Text(person.displayName).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    private func lines(_ preview: PersonMergePreview) -> some View {
        let leaving = preview.leaving.displayName, staying = preview.staying.displayName
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(leaving) joins \(staying). Every story, name and photo moves to \(staying).")
                .font(.body).foregroundStyle(Theme.ink)
                .accessibilityIdentifier("merge.confirm.text")
            // Plan decision 1: said only when it applies.
            if preview.staysHidden {
                Text("\(staying) stays hidden, because one of them is.").font(.subheadline).foregroundStyle(Theme.ink)
            }
            if preview.staysOutOfAI {
                Text("\(staying) stays out of the AI's view, because one of them is.").font(.subheadline).foregroundStyle(Theme.ink)
            }
            Text("You can undo this for a few seconds only.").font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button(action: mergeTapped) {
                Text("Merge").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .tint(Theme.oliveOnFill)
            .accessibilityIdentifier("merge.confirm.merge")
            Button { dismiss() } label: {
                Text("Cancel").font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .tint(Theme.oliveOnFill)
            .accessibilityIdentifier("merge.confirm.cancel")
        }
    }

    /// A merge hands its receipt to the host, which closes the sheet. A refused one closes it here; the host says why.
    private func mergeTapped() {
        if let receipt = viewModel.merge() { onMerged(receipt) } else { dismiss() }
    }
}
