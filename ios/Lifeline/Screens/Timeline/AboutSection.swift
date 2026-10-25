import LifelineKit
import SwiftUI

/// "About": facts, feelings and goals (M7). They are not moments, so they have no band and no
/// date here; each row is its title and the person's words.
struct AboutSection: View {
    let rows: [MemoryRow]
    let actions: MemoryRowActions

    var body: some View {
        Section {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Button { actions.open(row) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.memory.title).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                            Text("“\(row.memory.summaryQuote)”").font(.footnote).foregroundStyle(Theme.stone).lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.memory.title)
                    .accessibilityIdentifier("about.row")
                    Menu {
                        Button("Hide from timeline", systemImage: "eye.slash") { actions.hide(row) }
                        Button("Delete…", systemImage: "trash", role: .destructive) { actions.delete(row) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.stone).padding(.top, 8)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("about.more")
                }
            }
        } header: {
            HStack {
                Text("About").font(.system(.title3, design: .serif)).foregroundStyle(Theme.ink).textCase(nil)
                Spacer()
                Text(rows.count == 1 ? "1 thing about your life" : "\(rows.count) things about your life").font(.caption).foregroundStyle(Theme.stone)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timeline.about")
        }
    }
}
