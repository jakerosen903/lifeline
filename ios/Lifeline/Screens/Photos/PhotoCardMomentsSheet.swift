import LifelineKit
import SwiftUI

/// The photo card's one sheet, in two modes. `holding`: the kept memories that hold the photo, each with "Remove" (the moments
/// row opens it). `choosing`: the memories that can take the photo's date, each with a switch that starts on, and
/// "Use for {n}" (the "Choose moments" link opens it). "Done" closes it and changes nothing.
struct PhotoCardMomentsSheet: View {
    enum Mode {
        case holding(remove: (Memory) -> Void)
        case choosing(use: ([Memory]) -> Void)
    }

    let title: String
    let memories: [Memory]
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    /// The memories switched off, in choosing mode. Every one starts on.
    @State private var unchosen: Set<MemoryID> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(memories) { memory in row(memory) }
                    .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .linenBackground()
            .accessibilityIdentifier("photoCard.momentsSheet")
            .safeAreaInset(edge: .bottom, spacing: 0) { useButton }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("photoCard.momentsDone")
                }
            }
        }
    }

    @ViewBuilder private func row(_ memory: Memory) -> some View {
        switch mode {
        case .holding(let remove):
            HStack(alignment: .center, spacing: 12) {
                Text(memory.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("photoCard.memory")
                Button { remove(memory) } label: { Text("Remove").frame(minHeight: 44) }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondaryText)
                    // Two lines must not sound the same to VoiceOver and Voice Control; the label starts with the visible text.
                    .accessibilityLabel("Remove from \(memory.title)")
                    .accessibilityIdentifier("photoCard.removeFromMemory")
            }
        case .choosing:
            Toggle(isOn: Binding(get: { !unchosen.contains(memory.id) },
                                 set: { on in if on { unchosen.remove(memory.id) } else { unchosen.insert(memory.id) } })) {
                Text(memory.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.olive)
            .frame(minHeight: 44)
            .accessibilityIdentifier("photoCard.chooseMoment")
        }
    }

    /// "Use for {n}" in choosing mode; disabled when every switch is off.
    @ViewBuilder private var useButton: some View {
        if case .choosing(let use) = mode {
            let chosen = memories.filter { !unchosen.contains($0.id) }
            Button {
                use(chosen)
                dismiss()
            } label: {
                Text(PhotoDatePart.chooseButton(count: chosen.count)).font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oliveOnFill)
            .disabled(chosen.isEmpty)
            .accessibilityIdentifier("photoCard.useChosen")
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}
