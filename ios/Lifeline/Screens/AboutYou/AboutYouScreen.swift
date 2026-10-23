import SwiftUI

/// Onboard1. Every field is optional; Skip saves an empty profile.
struct AboutYouScreen: View {
    let viewModel: AboutYouViewModel

    var body: some View {
        Form {
            AboutYouFields(viewModel: viewModel)
        }
        .scrollContentBackground(.hidden)
        .linenBackground()
    }
}

/// The fields themselves, so Settings can place them inside its own Form.
struct AboutYouFields: View {
    @Bindable var viewModel: AboutYouViewModel

    var body: some View {
        Group {
            Section {
                Text("About you").titleStyle()
                Text("Everything here is optional. You can change it in Settings.")
                    .foregroundStyle(Theme.stone)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Your name", text: $viewModel.name)
                    .accessibilityIdentifier("aboutYou.name")
                Toggle("Do you want to add your birthday?", isOn: $viewModel.hasBirthday)
                    .accessibilityIdentifier("aboutYou.hasBirthday")
                if viewModel.hasBirthday {
                    DatePicker("Birthday", selection: $viewModel.birthday, in: ...Date.now, displayedComponents: .date)
                        .accessibilityIdentifier("aboutYou.birthday")
                }
                TextField("Where did you grow up?", text: $viewModel.birthPlace)
                    .accessibilityIdentifier("aboutYou.birthPlace")
            }

            Section("Anything useful for me to know?") {
                TextEditor(text: $viewModel.freeText)
                    .frame(minHeight: 100)
                    .accessibilityIdentifier("aboutYou.freeText")
            }

            if let error = viewModel.error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button(viewModel.mode == .firstOpen ? "Continue" : "Save") { viewModel.save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.olive)
                    .accessibilityIdentifier("aboutYou.continue")
                if viewModel.mode == .firstOpen {
                    Button("Skip for now") { viewModel.skip() }
                        .foregroundStyle(Theme.stone)
                        .accessibilityIdentifier("aboutYou.skip")
                }
            }
            .listRowBackground(Color.clear)
        }
    }
}
