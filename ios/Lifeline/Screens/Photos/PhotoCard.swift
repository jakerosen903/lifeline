import LifelineKit
import SwiftUI

/// The photo card of a photo session, on the landing and on the session's page: the photo with its caption, which kept
/// memories hold it, one-tap offers to add it to the pages the story named and to use its date, and removals.
/// An offer has no "No": a tap accepts it, and an offer left alone changes nothing. The view holds no rule; the card
/// it draws comes from `PhotoStory.card`. Nothing here says what the photo shows.
struct PhotoCard: View {
    let viewModel: PhotoCardViewModel
    let cache: PhotoImageCache

    var body: some View {
        if let card = viewModel.card {
            VStack(alignment: .leading, spacing: 12) {
                SessionPhoto(photo: card.photo, cache: cache)
                if let caption = PhotoCaption.taken(card.photo.takenAt) {
                    Text(caption).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                if card.hasPendingMoments {
                    Text("This photo goes on each moment you keep.")
                        .font(.system(.subheadline, design: .serif)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("photoCard.pending")
                }
                ForEach(card.memories) { memory in memoryRow(memory) }
                ForEach(card.pageOffers) { page in
                    Button { viewModel.addToPage(page) } label: { control(viewModel.offerTitle(page)) }
                        .buttonStyle(.bordered).tint(Theme.oliveOnFill)
                        .accessibilityIdentifier("photoCard.addToPage")
                }
                ForEach(card.dateOffers) { offer in dateOffer(offer) }
                if viewModel.showsRemoveFromStory {
                    Button(role: .destructive) { Task { await viewModel.removeFromStory() } } label: { control("Remove the photo from this story") }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("photoCard.removeFromStory")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sand))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("photoCard")
        }
    }

    /// A kept memory that holds the photo, with "Remove". The spoken label names the memory, so two rows are told apart.
    private func memoryRow(_ memory: Memory) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(memory.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("photoCard.memory")
            Button { Task { await viewModel.removeFromMemory(memory) } } label: {
                Text("Remove").frame(minHeight: 44)
            }
            .buttonStyle(.borderless).foregroundStyle(Theme.secondaryText)
            .accessibilityLabel("Remove from \(memory.title)")
            .accessibilityIdentifier("photoCard.removeFromMemory")
        }
    }

    /// "The photo is dated 14 July 2019. Use that for when this happened?" for one memory, named above it.
    private func dateOffer(_ offer: PhotoStoryCard.DateOffer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(offer.memory.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.oliveText)
            Text("The photo is dated \(PhotoCaption.longDate(offer.date) ?? "that day"). Use that for when this happened?")
                .font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Button { viewModel.useDate(offer) } label: { control("Use this date") }
                .buttonStyle(.bordered).tint(Theme.oliveOnFill)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoCard.useDate")
    }

    /// Wraps at the largest text size and never shrinks below 44 points.
    private func control(_ title: String) -> some View {
        Text(title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
    }
}
