import SwiftUI

/// Year labels across the width, shared by every band below it.
struct YearAxis: View {
    let years: ClosedRange<Int>

    var body: some View {
        GeometryReader { geo in
            let labels = Self.labels(for: years)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.stone.opacity(0.4)).frame(height: 1).offset(y: 14)
                ForEach(labels, id: \.self) { year in
                    Text(String(year))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.stone)
                        .position(x: Self.x(for: year, in: years, width: geo.size.width), y: 6)
                }
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(years.lowerBound) to \(years.upperBound)")
        .accessibilityIdentifier("timeline.axis")
    }

    static func labels(for years: ClosedRange<Int>) -> [Int] {
        let span = years.count
        let step = span <= 12 ? 2 : (span <= 30 ? 5 : 10)
        let first = (years.lowerBound / step) * step
        return stride(from: first, through: years.upperBound, by: step).filter { years.contains($0) }
    }

    /// Horizontal position of a year's start; the band for one year runs from year to year + 1.
    static func x(for year: Int, in years: ClosedRange<Int>, width: CGFloat) -> CGFloat {
        let total = CGFloat(years.count)
        return (CGFloat(year - years.lowerBound) / total) * width
    }
}
