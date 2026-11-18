import LifelineKit
import SwiftUI

/// The life map's frame around its rows: period names on top, every other period shaded behind the
/// rows, and the years along the bottom with "now" at the right edge. Decorative for VoiceOver:
/// each row's label already says its years.
struct LifeMapAxis {
    /// The labels that fit: every fifth year, thinned to every tenth (and so on) until neighbours do
    /// not touch, without one so close to the right edge that it runs into "now". Pure.
    static func visibleYears(_ years: [Int], startYear: Int, endYear: Int, width: CGFloat, labelWidth: CGFloat) -> [Int] {
        let units = CGFloat(endYear - startYear + 1)
        guard width > 0, units > 0, !years.isEmpty else { return [] }
        let unitWidth = width / units
        var step = 1
        while CGFloat(5 * step) * unitWidth < labelWidth && step < years.count { step += 1 }
        return years.enumerated().compactMap { index, year in
            let x = CGFloat(year - startYear) * unitWidth
            return index % step == 0 && x + 2 * labelWidth <= width ? year : nil
        }
    }

    /// The band's x and width across `width`.
    static func span(_ band: LifeMap.Band, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        (CGFloat(band.start) * width, CGFloat(band.end - band.start) * width)
    }
}

/// The period names along the top: each one inside its own column, truncated when the column is narrow.
struct LifeMapPeriodNames: View {
    let map: LifeMap
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(map.periods.enumerated()), id: \.offset) { _, band in
                let span = LifeMapAxis.span(band, width: geometry.size.width)
                Text(band.name)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: max(span.width - 4, 0), alignment: .leading)
                    .offset(x: span.x + 4)
            }
        }
        .font(.caption).foregroundStyle(Theme.secondaryText)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Every other period shaded, behind the rows, so a row's place in a life reads at a glance.
struct LifeMapPeriodColumns: View {
    let map: LifeMap

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(map.periods.enumerated()), id: \.offset) { index, band in
                if index % 2 == 1 {
                    let span = LifeMapAxis.span(band, width: geometry.size.width)
                    Rectangle().fill(Theme.sand)
                        .frame(width: span.width, height: geometry.size.height)
                        .offset(x: span.x)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The years along the bottom, on a hairline, with "now" at the right edge.
struct LifeMapYears: View {
    let map: LifeMap
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let units = CGFloat(map.endYear - map.startYear + 1)
            ZStack(alignment: .topLeading) {
                ForEach(LifeMapAxis.visibleYears(map.axisYears, startYear: map.startYear, endYear: map.endYear, width: width, labelWidth: labelWidth), id: \.self) { year in
                    Text(String(year)).offset(x: CGFloat(year - map.startYear) / units * width)
                }
                Text("now").frame(width: width, alignment: .trailing)
            }
        }
        .font(.caption).monospacedDigit().foregroundStyle(Theme.secondaryText)
        .lineLimit(1)
        .frame(height: height)
        .padding(.top, 2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .accessibilityHidden(true)
    }
}
