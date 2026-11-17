import PhotosUI
import SwiftUI

/// The system picker inside the start sheet, for "All photos" and for a start with no access or nothing to show. It
/// needs no permission (decision 18 of S4), and the picked item goes through the S4 picked-copy path. Inline, so the
/// session starts from the one sheet's dismissal and no second sheet is ever in the way.
/// Under `-uiTesting-pickPhoto <path>` the picker is skipped and that file is picked at once (S4 decision 22).
struct AllPhotosPicker: View {
    let viewModel: PhotoStoryStartViewModel
    let pickPhotoPath: String?
    @State private var selection: PhotosPickerItem?

    var body: some View {
        if let pickPhotoPath {
            Color.clear.task { await viewModel.picked(fileAt: URL(fileURLWithPath: pickPhotoPath)) }
        } else {
            PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) {
                Text("All photos")
            }
            .photosPickerStyle(.inline)
            // Only the bottom bar (Cancel and Add) goes: the sheet has its own Cancel, and one photo at a time needs no Add.
            // The top keeps Photos and Collections and search, the person's only way to albums here without access.
            .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
            .disabled(viewModel.isAdding)
            .onChange(of: selection) { _, item in
                guard let item else { return }
                // Cleared at once, so picking the same photo again after an error is a change too.
                selection = nil
                Task { await viewModel.picked(item) }
            }
        }
    }
}
