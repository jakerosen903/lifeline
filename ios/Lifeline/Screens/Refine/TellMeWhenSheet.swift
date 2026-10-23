import LifelineKit
import SwiftUI

/// "Tell me when": a year, around a year, between two years, or how old I was. What is chosen is
/// stored as the person's word (origin `stated`) and shown as said. Never a guess.
struct TellMeWhenSheet: View {
    enum Shape: String, CaseIterable, Identifiable {
        case year = "A year", around = "Around a year", between = "Between two years", age = "How old I was"
        var id: String { rawValue }
    }

    let title: String
    let birthDate: CivilDate?
    let onSave: (TimeRange) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shape: Shape = .year
    @State private var year: Int
    @State private var year2: Int
    @State private var age = 8

    private static let years = Array(AnchorPhrase.yearRange)

    init(title: String, birthDate: CivilDate?, onSave: @escaping (TimeRange) -> Void) {
        self.title = title
        self.birthDate = birthDate
        self.onSave = onSave
        let now = CivilDate.today().year
        _year = State(initialValue: now - 20)
        _year2 = State(initialValue: now - 15)
    }

    private var range: TimeRange? {
        switch shape {
        case .year: return .stated(year: year)
        case .around: return .stated(around: year)
        case .between: return .stated(between: year, and: year2)
        case .age:
            guard let birthDate else { return nil }
            return .stated(age: .approximate(center: age, slack: 0), birth: birthDate, evidence: "about \(age)")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Theme.ink)
                Picker("Shape", selection: $shape) {
                    ForEach(Shape.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Theme.olive)
                .accessibilityIdentifier("when.shape")

                switch shape {
                case .year, .around:
                    yearPicker($year, id: "when.year")
                case .between:
                    HStack {
                        yearPicker($year, id: "when.year")
                        Text("to").foregroundStyle(Theme.stone)
                        yearPicker($year2, id: "when.year2")
                    }
                case .age:
                    if birthDate == nil {
                        Text("Add your birthday in Settings to place memories by age.")
                            .font(.footnote).foregroundStyle(Theme.stone)
                            .accessibilityIdentifier("when.needsBirthday")
                    } else {
                        Picker("Age", selection: $age) {
                            ForEach(0...110, id: \.self) { Text("about \($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityIdentifier("when.age")
                    }
                }

                if let range {
                    Text("Shown as “\(range.displayText)”").font(.footnote).foregroundStyle(Theme.stone)
                }
                Spacer()
            }
            .padding(24)
            .linenBackground()
            .navigationTitle("Tell me when")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let range { onSave(range); dismiss() } }
                        .disabled(range == nil)
                        .accessibilityIdentifier("when.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func yearPicker(_ selection: Binding<Int>, id: String) -> some View {
        Picker("Year", selection: selection) {
            ForEach(Self.years, id: \.self) { Text(String($0)).tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxHeight: 160)
        .accessibilityIdentifier(id)
    }
}
