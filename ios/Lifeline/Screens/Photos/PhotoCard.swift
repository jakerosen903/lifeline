import LifelineKit
import SwiftUI

/// The photo card of a photo session, on the landing and on the session's page, in the spec's four parts: the photo with its
/// caption and the moments row; the pages as chips (`PhotoCardPages`); the date (`PhotoCardDate`); and, on the session's
/// page, "Remove the photo from this story". A choice changes the state of its control and nothing else, so the card keeps
/// its layout; the one exception is the pages part, which has two layouts, open and done, by the owner's request (spec
/// part 3). An offer has no "No". The view holds no rule; what it draws comes from `PhotoStory.card` and `PhotoDatePart`.
/// Nothing here says what the photo shows.
struct PhotoCard: View {
    let viewModel: PhotoCardViewModel
    let cache: PhotoImageCache
    /// "Remove the photo from this story" asks first, as "Remove photo…" in the viewer does (S4): the photo can leave Lifeline.
    @State private var confirmingRemoveFromStory = false
    @State private var sheet: Sheet?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The one sheet, in its two modes. "Choose moments" keeps the memories offered when it opened: the write checks each
    /// range, so a memory that changed elsewhere meanwhile is left alone.
    private enum Sheet: Identifiable {
        case moments
        case choosing([Memory])
        var id: String {
            switch self {
            case .moments: "moments"
            case .choosing: "choosing"
            }
        }
    }

    var body: some View {
        if let card = viewModel.card {
            VStack(alignment: .leading, spacing: 16) {
                photoAndMoments(card)
                if card.showsPagesPart(keeping: viewModel.keptPages) {
                    PhotoCardPages(card: card, kept: viewModel.keptPages, onToggle: { page in Task { await viewModel.toggle(page) } },
                                   onDone: { viewModel.donePages() }, onEdit: { viewModel.editPages() })
                }
                let part = viewModel.datePart
                if part != .hidden {
                    PhotoCardDate(part: part, onUse: { viewModel.useDate(for: $0, offered: $0) }, onChoose: {
                        if case .offer(let offer) = part { sheet = .choosing(offer.memories) }
                    }, onUndo: { viewModel.undoDate() })
                }
                if viewModel.showsRemoveFromStory { removeFromStory }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("photoCard")
            .sheet(item: $sheet) { route in momentsSheet(route) }
            // The last "Remove" leaves the moments list empty, with no title: the sheet closes instead of standing blank.
            .onChange(of: card.memories.isEmpty) { _, isEmpty in
                if isEmpty, case .moments = sheet { sheet = nil }
            }
        }
    }

    /// The photo, small, with its caption and the row that says which moments hold it. At the accessibility sizes the
    /// row goes under the photo, so its words have the card's width.
    private func photoAndMoments(_ card: PhotoStoryCard) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            SessionPhoto(photo: card.photo, cache: cache).frame(width: 104)
            VStack(alignment: .leading, spacing: 4) {
                if let caption = PhotoCaption.taken(card.photo.takenAt) {
                    Text(caption).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                momentsRow(card)
            }
        }
    }

    /// "This photo goes on each moment you keep." while a moment waits (a text: it does not open, decision 9);
    /// "On {n} moments from this story" once it opens; nothing when there is nothing to say.
    @ViewBuilder private func momentsRow(_ card: PhotoStoryCard) -> some View {
        if let line = card.momentsLine {
            if card.momentsLineOpens {
                Button { sheet = .moments } label: {
                    HStack(spacing: 8) {
                        Text(line).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photoCard.moments")
            } else {
                Text(line)
                    .font(.system(.subheadline, design: .serif)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photoCard.pending")
            }
        }
    }

    private var removeFromStory: some View {
        Button(role: .destructive) { confirmingRemoveFromStory = true } label: {
            Text("Remove the photo from this story").multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("photoCard.removeFromStory")
        .confirmationDialog("Remove this photo?", isPresented: $confirmingRemoveFromStory, titleVisibility: .visible) {
            Button("Remove photo", role: .destructive) { Task { await viewModel.removeFromStory() } }
                .accessibilityIdentifier("photoCard.confirmRemoveFromStory")
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It leaves this story. The original stays in your photo library.")
        }
    }

    /// Built from the view model each time it draws, so a "Remove" in the sheet shows at once.
    @ViewBuilder private func momentsSheet(_ route: Sheet) -> some View {
        switch route {
        case .moments:
            PhotoCardMomentsSheet(title: viewModel.card?.momentsLine ?? "", memories: viewModel.card?.memories ?? [],
                                  mode: .holding(remove: { memory in Task { await viewModel.removeFromMemory(memory) } }))
        case .choosing(let memories):
            PhotoCardMomentsSheet(title: "Choose moments", memories: memories, mode: .choosing(use: { viewModel.useDate(for: $0, offered: memories) }))
        }
    }
}
