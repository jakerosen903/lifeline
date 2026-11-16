import LifelineKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// "Add a photo": the system picker, one image at a time, then the picked file to `onFile`. Under
    /// `-uiTesting-pickPhoto <path>` the picker is skipped and that file goes to `onFile` at once.
    func addPhotoFlow(isPresented: Binding<Bool>, deps: Dependencies, onFile: @escaping (URL, String?) async -> Void,
                      onError: @escaping (String) -> Void) -> some View {
        modifier(AddPhotoFlow(isPresented: isPresented, pickPhotoPath: deps.pickPhotoPath, onFile: onFile, onError: onError))
    }
}

/// Decision 18: `.photosPicker` from the shared library, which gives the asset identifier with no permission
/// prompt (the person grants access to the one photo they choose). The photo arrives as a file, never as one
/// `Data` in memory, so a very large image does not spike memory.
struct AddPhotoFlow: ViewModifier {
    @Binding var isPresented: Bool
    let pickPhotoPath: String?
    let onFile: (URL, String?) async -> Void
    let onError: (String) -> Void
    @State private var selection: PhotosPickerItem?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let pickPhotoPath {
            // UI tests cannot drive the out-of-process picker (decision 22). The test owns this file; it is not removed.
            content.onChange(of: isPresented) { _, presented in
                guard presented else { return }
                isPresented = false
                Task { await onFile(URL(fileURLWithPath: pickPhotoPath), nil) }
            }
        } else {
            content
                .photosPicker(isPresented: $isPresented, selection: $selection, matching: .images,
                              preferredItemEncoding: .current, photoLibrary: .shared())
                .onChange(of: selection) { _, item in
                    guard let item else { return }
                    // Cleared at once, so picking the same photo again is a change too.
                    selection = nil
                    Task { await receive(item) }
                }
        }
    }

    private func receive(_ item: PhotosPickerItem) async {
        do {
            guard let picked = try await item.loadTransferable(type: PickedPhotoFile.self) else { throw PhotoImport.Error.unreadable }
            // The copy is ours; it goes once the library has made its own downscaled copy, or refused it.
            defer { try? FileManager.default.removeItem(at: picked.url) }
            await onFile(picked.url, item.itemIdentifier)
        } catch {
            onError("Could not add this photo: \(error.localizedDescription)")
        }
    }
}

/// The picked image as a file. The system's file lives only while the importing closure runs, so it is copied
/// into the temporary folder under a fresh name that keeps its extension.
struct PickedPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let ext = received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)"))
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedPhotoFile(url: copy)
        }
    }
}
