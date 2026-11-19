import LifelineKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// "Add a photo": the system picker, up to 20 photos in the order picked, then each picked file to `onFile`, one
    /// after the other. `shelf` shows "Adding photo {i} of {n}…" from the moment the picked items arrive, then the
    /// pick's one failure line, and its finished adds reload the page's photos.
    /// Under `-uiTesting-pickPhotos <path>,<path>` (or `-uiTesting-pickPhoto <path>`) the picker is skipped and those
    /// files go to `onFile` at once, in order.
    func addPhotoFlow(isPresented: Binding<Bool>, deps: Dependencies, shelf: PhotoShelf?, onFile: @escaping (URL, String?) async -> Void,
                      onError: @escaping (String) -> Void) -> some View {
        modifier(AddPhotoFlow(isPresented: isPresented, pickPhotoPaths: deps.addPhotoPaths, shelf: shelf, onFile: onFile, onError: onError))
    }
}

/// Decision 18: `.photosPicker` from the shared library, which gives the asset identifier with no permission
/// prompt (the person grants access to the photos they choose). Each photo arrives as a file, never as one
/// `Data` in memory, so a very large image does not spike memory. Part 4 (decision 17): the photos are received
/// and added one after the other, never at the same time, so one temporary copy and one image are held at a time.
struct AddPhotoFlow: ViewModifier {
    /// The most photos one visit to the picker can give (part 4).
    static let pickLimit = 20

    @Binding var isPresented: Bool
    let pickPhotoPaths: [String]?
    let shelf: PhotoShelf?
    let onFile: (URL, String?) async -> Void
    let onError: (String) -> Void
    @State private var selection: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        // A finished add can write a missing file back under the same name; the page's photos load again.
        picker(content).environment(\.photoReloadKey, shelf?.addsFinished ?? 0)
    }

    @ViewBuilder
    private func picker(_ content: Content) -> some View {
        if let pickPhotoPaths {
            // UI tests cannot drive the out-of-process picker (decision 22). The test owns these files; they are not removed.
            content.onChange(of: isPresented) { _, presented in
                guard presented else { return }
                isPresented = false
                let files = pickPhotoPaths.map { URL(fileURLWithPath: $0) }
                Task { await addEach(files) { file in await onFile(file, nil) } }
            }
        } else {
            content
                .photosPicker(isPresented: $isPresented, selection: $selection, maxSelectionCount: Self.pickLimit,
                              selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
                .onChange(of: selection) { _, items in
                    // Cleared at once, so picking the same photos again is a change too. The clear itself comes back here empty.
                    guard !items.isEmpty else { return }
                    selection = []
                    Task { await addEach(items) { item in try await PickedPhotoFile.receive(item, onFile: onFile) } }
                }
        }
    }

    /// Hands the picked items over one after the other, in order. A photo that fails does not stop the others.
    /// The line shows before the first hand-over: it can take seconds for a photo in iCloud. A kill keeps every
    /// photo already added; each add is its own write.
    @MainActor
    private func addEach<Item: Sendable>(_ items: [Item], _ add: @MainActor (Item) async throws -> Void) async {
        let shelf = shelf
        shelf?.beginAdding(count: items.count)
        defer { shelf?.endAdding() }
        for item in items {
            do { try await add(item) } catch {
                // A pick with no shelf has no line to count in; it says so at once, as one photo always did.
                if let shelf { shelf.failed(error.localizedDescription) } else { PhotoAddProgress.failureLine(failed: 1, lastError: error.localizedDescription).map(onError) }
            }
            shelf?.finishedOne()
        }
    }
}

/// The picked image as a file. The system's file lives only while the importing closure runs, so it is copied
/// into the temporary folder under a fresh name that keeps its extension. Launch removes a copy a kill left behind.
struct PickedPhotoFile: Transferable {
    let url: URL

    /// One picked item's file to `onFile`, with its asset identifier. "Add a photo" (once per item) and "All photos" share this path.
    @MainActor static func receive(_ item: PhotosPickerItem, onFile: (URL, String?) async -> Void) async throws {
        guard let picked = try await item.loadTransferable(type: PickedPhotoFile.self) else { throw PhotoImport.Error.unreadable }
        // The copy is ours; it goes once the library has made its own downscaled copy, or refused it.
        defer { try? FileManager.default.removeItem(at: picked.url) }
        await onFile(picked.url, item.itemIdentifier)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let copy = PickedPhotoCopy.url(in: FileManager.default.temporaryDirectory, extension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedPhotoFile(url: copy)
        }
    }
}
