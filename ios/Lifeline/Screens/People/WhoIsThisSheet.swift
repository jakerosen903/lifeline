import LifelineKit
import SwiftUI

/// PC2: who is this name? Radio rows for the people it could be, "Someone new", "Someone else" for the rest,
/// "Not a person" as a quiet row, one checkbox for the other moments, and Done. The presenter sets the
/// detents' host (`.sheet`); this view asks for medium and large.
struct WhoIsThisSheet: View {
    @State var viewModel: WhoIsThisViewModel
    let onDone: (WhoIsThisViewModel.Outcome) -> Void
    @State private var showsEveryone = false
    @State private var errorText: String?

    private var options: WhoIsThisOptions { viewModel.options }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                VStack(spacing: 8) {
                    ForEach(options.rows) { optionRow($0) }
                    newRow
                    everyoneElse
                }
                notAPersonRow
                if options.otherMoments > 0 { groupRow }
                if let errorText { ErrorLine(text: errorText) }
                doneButton
                Text("Nothing is deleted. You can change this again at any time.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
        }
        .background(Theme.linen)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("who.sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who is \u{201C}\(options.saidName)\u{201D} here?")
                .font(.system(.title2, design: .serif).weight(.medium)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let quote = options.quote, !quote.isEmpty {
                Text("You said: \u{201C}\(quote)\u{201D}").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func optionRow(_ row: WhoIsThisOptions.Row) -> some View {
        let person: PersonID? = if case .person(let id) = row.target { id } else { nil }
        return choiceRow(row.target, identifier: "who.option", title: row.title, line: row.line, label: "\(row.title). \(row.line)") {
            PersonFace(id: person.map { EntityID(rawValue: $0.rawValue) } ?? EntityID(rawValue: row.title), name: row.title,
                       cover: person.flatMap(viewModel.cover(of:)), cache: viewModel.photoImages, size: 40)
        }
    }

    private var newRow: some View {
        choiceRow(.someoneNew, identifier: "who.new", title: "Someone new", line: nil, label: "Someone new") {
            Image(systemName: "plus").foregroundStyle(Theme.secondaryText)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Theme.secondaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                .accessibilityHidden(true)
        }
    }

    private func choiceRow<Face: View>(_ target: PersonLinkActions.Target, identifier: String, title: String, line: String?,
                                       label: String, @ViewBuilder face: () -> Face) -> some View {
        let isSelected = viewModel.selected == target
        return Button { viewModel.selected = target } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Theme.olive : Theme.secondaryText)
                    .accessibilityHidden(true)
                face()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                    if let line { Text(line).font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Theme.olive : Theme.hairline, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var everyoneElse: some View {
        if !options.everyoneElse.isEmpty {
            DisclosureGroup(isExpanded: $showsEveryone) {
                VStack(spacing: 8) {
                    ForEach(options.everyoneElse) { optionRow($0) }
                }
                .padding(.top, 8)
            } label: {
                Text("Someone else").font(.body.weight(.medium)).foregroundStyle(Theme.oliveText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .tint(Theme.oliveText)
            .accessibilityIdentifier("who.else")
        }
    }

    private var notAPersonRow: some View {
        let isSelected = viewModel.selected == .notAPerson
        return Button { viewModel.selected = .notAPerson } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                Text("Not a person")
            }
            .font(.subheadline).foregroundStyle(isSelected ? Theme.ink : Theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("who.notAPerson")
    }

    private var groupRow: some View {
        Button { viewModel.wholeGroup.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: viewModel.wholeGroup ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundStyle(viewModel.wholeGroup ? Theme.olive : Theme.secondaryText)
                    .accessibilityHidden(true)
                Text(WhoIsThisOptions.groupLabel(options.otherMoments))
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sand))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WhoIsThisOptions.groupLabel(options.otherMoments))
        .accessibilityAddTraits(viewModel.wholeGroup ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("who.group")
    }

    private var doneButton: some View {
        Button {
            let outcome = viewModel.done()
            if case .failed(let message) = outcome { errorText = message } else { onDone(outcome) }
        } label: {
            Text("Done").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        .tint(Theme.oliveOnFill)
        .accessibilityIdentifier("who.done")
    }
}
