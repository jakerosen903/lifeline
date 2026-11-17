import LifelineKit
import Synchronization
import UIKit

/// The photo library under `-uiTesting`: three generated photos, newest first, and the access that
/// `-uiTesting-photoAccess <notAsked|full|limited|none|empty>` names (default `full`; `empty` is full access to an
/// empty album). From `notAsked`, `requestAccess()` answers `full`, and so does every later `access()` in that launch.
final class ScriptedPhotoPickSource: PhotoPickSource {
    private let current: Mutex<PhotoAccess>
    private let served: [LibraryPhoto]
    private let folder: URL

    /// Writes the three photos into `folder`. Their dates differ so a test can tell which one it picked.
    init(mode: String?, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photos: [(name: String, rgb: Int, takenAt: String)] = [
            ("scripted-2019", 0x5B7F3A, "2019:07:14 10:00:00"),
            ("scripted-2015", 0x3A5B7F, "2015:05:02 09:30:00"),
            ("scripted-2008", 0x7F3A5B, "2008:08:20 18:15:00"),
        ]
        for photo in photos {
            try GeneratedPhoto.write(to: folder.appending(path: "\(photo.name).jpg"), width: 400, height: 300, rgb: photo.rgb, takenAt: photo.takenAt)
        }
        self.folder = folder
        self.served = mode == "empty" ? [] : photos.map { LibraryPhoto(id: $0.name) }
        self.current = Mutex(Self.access(mode))
    }

    func access() -> PhotoAccess { current.withLock { $0 } }

    func requestAccess() async -> PhotoAccess {
        current.withLock { access in
            if access == .notAsked { access = .full }
            return access
        }
    }

    func photos() async -> [LibraryPhoto] {
        switch access() {
        case .full, .limited: served
        case .notAsked, .none: []
        }
    }

    func thumbnail(for photo: LibraryPhoto, side: CGFloat) async -> UIImage? {
        UIImage(contentsOfFile: url(of: photo).path)?.preparingForDisplay()
    }

    /// A fresh copy, as PhotoKit writes one: the caller removes it, and the served photo stays for a second pick.
    func file(for photo: LibraryPhoto) async throws -> URL {
        let copy = PickedPhotoCopy.url(in: FileManager.default.temporaryDirectory, extension: "jpg")
        try FileManager.default.copyItem(at: url(of: photo), to: copy)
        return copy
    }

    private func url(of photo: LibraryPhoto) -> URL { folder.appending(path: "\(photo.id).jpg") }

    private static func access(_ mode: String?) -> PhotoAccess {
        switch mode {
        case "notAsked": .notAsked
        case "limited": .limited
        case "none": .none
        default: .full
        }
    }
}
