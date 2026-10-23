import SwiftUI

/// Five bars that move while the app listens. Speech makes them swell; quiet makes them
/// breathe slowly; an interruption holds them still. The motion is a function of time, so it
/// never depends on audio levels reaching the view. Reduced motion shows the still state.
struct ListeningIndicator: View {
    enum Mode { case quiet, speaking, paused }
    let mode: Mode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barCount = 5
    private static let height: CGFloat = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: mode == .paused || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(mode == .paused ? Theme.stone : Theme.olive)
                        .frame(width: 4, height: Self.height * Self.scale(bar: index, at: t, mode: mode))
                }
            }
            .frame(height: Self.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("session.listening")
    }

    private var label: String {
        switch mode {
        case .quiet: "Listening"
        case .speaking: "Hearing you"
        case .paused: "Paused"
        }
    }

    /// Bar height as a fraction of full height, in 0.2...1.
    static func scale(bar: Int, at time: TimeInterval, mode: Mode) -> CGFloat {
        let phase = Double(bar) * 0.9
        switch mode {
        case .paused:
            return 0.3
        case .quiet:
            return 0.25 + 0.1 * (1 + sin(time * 1.6 + phase)) / 2
        case .speaking:
            let fast = sin(time * 7 + phase), slow = sin(time * 2.3 + phase * 1.7)
            return 0.35 + 0.65 * (fast * 0.6 + slow * 0.4 + 1) / 2
        }
    }
}
