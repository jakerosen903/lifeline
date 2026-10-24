import LifelineKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings → "Your copy": Export a copy… and Restore from a copy… (M6).
struct YourCopySection: View {
    @Bindable var viewModel: BackupViewModel
    @State private var picking = false

    var body: some View {
        Section {
            Button("Export a copy…") { viewModel.export() }
                .disabled(viewModel.progressText != nil)
                .accessibilityIdentifier("settings.export")
            if let progress = viewModel.progressText {
                Label(progress, systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(Theme.stone)
                    .accessibilityIdentifier("settings.exportProgress")
            }
            if let last = viewModel.lastExportText {
                Text(last).font(.footnote).foregroundStyle(Theme.stone).accessibilityIdentifier("settings.lastExport")
            }
            Button("Restore from a copy…") {
                if let path = viewModel.testRestorePath { viewModel.chose(URL(fileURLWithPath: path)) } else { picking = true }
            }
            .accessibilityIdentifier("settings.restore")
            if let summary = viewModel.summaryText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary).font(.footnote).foregroundStyle(Theme.ink).accessibilityIdentifier("restore.summary")
                    Text("Replace everything on this phone with this copy?").font(.subheadline)
                    Text("A copy of what is on the phone now is saved to Files first.").font(.footnote).foregroundStyle(Theme.stone)
                    HStack {
                        Button("Replace", role: .destructive) { viewModel.confirmRestore() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("restore.confirm")
                        Button("Cancel") { viewModel.cancelRestore() }.buttonStyle(.bordered)
                    }
                }
            }
            if let relaunch = viewModel.relaunchText {
                Label(relaunch, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Theme.olive)
                    .accessibilityIdentifier("restore.relaunch")
            }
            if let error = viewModel.error {
                Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("settings.backupError")
            }
        } header: {
            Text("Your copy")
        } footer: {
            Text("One file with every recording, memory and date. Nothing leaves the phone unless you share the file.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "lifeline") ?? .zip, .zip]) { result in
            if case .success(let url) = result { viewModel.chose(url) }
        }
        .sheet(item: $viewModel.shareURL, onDismiss: viewModel.shareClosed) { url in
            ShareSheet(items: [url])
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The system share sheet, for the exported file.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
