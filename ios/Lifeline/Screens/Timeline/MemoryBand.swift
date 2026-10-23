import LifelineKit
import SwiftUI

/// A memory on the year axis: a light bar for the possible band, a darker one for the likely
/// band, a dot for a stated day or month. Below it the title and the honest range text.
struct MemoryBand: View {
    let row: MemoryRow
    let axis: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let axis, let lo = row.memory.range.earliest, let hi = row.memory.range.latest {
                GeometryReader { geo in
                    let width = geo.size.width
                    let x0 = YearAxis.x(for: lo.year, in: axis, width: width)
                    let x1 = YearAxis.x(for: hi.year + 1, in: axis, width: width)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.olive.opacity(row.isGuess ? 0.25 : 0.6))
                            .frame(width: max(6, x1 - x0), height: 6).offset(x: x0)
                        if let ls = row.memory.range.likelyStart, let le = row.memory.range.likelyEnd {
                            let lx0 = YearAxis.x(for: ls.year, in: axis, width: width), lx1 = YearAxis.x(for: le.year + 1, in: axis, width: width)
                            Capsule().fill(Theme.olive.opacity(0.7)).frame(width: max(6, lx1 - lx0), height: 6).offset(x: lx0)
                        }
                        if row.memory.range.granularity == .day || row.memory.range.granularity == .month {
                            Circle().fill(Theme.olive).frame(width: 10, height: 10).offset(x: x0 - 2)
                        }
                    }
                }
                .frame(height: 10)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.memory.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if !row.durationText.isEmpty {
                    Text("\(row.durationText) in your voice").font(.caption).foregroundStyle(Theme.stone)
                }
            }
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(row.isGuess || !row.memory.range.isPlaced ? Theme.ochre : Theme.ink.opacity(0.8))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.memory.title) · \(row.subtitle)")
    }
}
