import LifelineKit
import SwiftUI

/// The fixed response to a serious disclosure, shown verbatim from the bundled text. The model
/// never writes any of it (principle: serious disclosures get pre-written words).
struct DisclosureCard: View {
    let text: String
    let crisisLine: CrisisLine
    let onOkay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("session.disclosureText")
            Link(destination: URL(string: "tel:\(crisisLine.number)")!) {
                Label("\(crisisLine.label): \(crisisLine.number)", systemImage: "phone")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Theme.olive)
            .accessibilityIdentifier("session.crisisLine")
            Button("Okay", action: onOkay)
                .buttonStyle(.bordered)
                .tint(Theme.olive)
                .accessibilityIdentifier("session.disclosureOkay")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sand))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.disclosure")
    }
}
