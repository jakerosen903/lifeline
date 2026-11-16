import Foundation

public struct PhotoID: TypedID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }

/// Where a photo's date or location came from. Only the file's own metadata, today.
public enum PhotoOrigin: String, Codable, Sendable { case exif }

/// A camera's date and time with no time zone. The camera does not say which zone its clock is in.
public struct PhotoTakenAt: Sendable, Hashable {
    public let date: CivilDate
    public let hour: Int
    public let minute: Int
    public let second: Int

    /// The camera form `2012:06:14 15:32:10`. Anything else is nil, so `0000:00:00 00:00:00` is nil too.
    public init?(exif: String) {
        let parts = exif.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.init(dateText: parts[0], dateSeparator: ":", timeText: parts[1])
    }

    /// The stored form `2012-06-14T15:32:10`.
    public init?(stored: String) {
        let parts = stored.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.init(dateText: parts[0], dateSeparator: "-", timeText: parts[1])
    }

    public var stored: String { String(format: "%@T%02d:%02d:%02d", date.iso, hour, minute, second) }

    private init?(dateText: Substring, dateSeparator: Character, timeText: Substring) {
        let d = dateText.split(separator: dateSeparator, omittingEmptySubsequences: false)
        let t = timeText.split(separator: ":", omittingEmptySubsequences: false)
        guard d.count == 3, t.count == 3, d[0].count == 4, d[1].count == 2, d[2].count == 2, t.allSatisfy({ $0.count == 2 }),
              let year = Int(d[0]), let month = Int(d[1]), let day = Int(d[2]),
              let hour = Int(t[0]), let minute = Int(t[1]), let second = Int(t[2]),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
              let date = CivilDate(year: year, month: month, day: day) else { return nil }
        self.date = date; self.hour = hour; self.minute = minute; self.second = second
    }
}

/// One stored picture. The file is `<photo id>.jpg`; the date and place it carried live only here.
public struct Photo: Sendable, Equatable, Identifiable {
    public var id: PhotoID
    public var fileName: String
    public var assetLocalID: String?
    public var takenAt: PhotoTakenAt?
    public var takenOrigin: PhotoOrigin?
    public var lat: Double?
    public var lon: Double?
    public var locationOrigin: PhotoOrigin?
    public var sha256: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var addedAt: Date

    public init(id: PhotoID = .init(), fileName: String, assetLocalID: String? = nil, takenAt: PhotoTakenAt? = nil, takenOrigin: PhotoOrigin? = nil,
                lat: Double? = nil, lon: Double? = nil, locationOrigin: PhotoOrigin? = nil,
                sha256: String, pixelWidth: Int, pixelHeight: Int, addedAt: Date) {
        self.id = id; self.fileName = fileName; self.assetLocalID = assetLocalID
        self.takenAt = takenAt; self.takenOrigin = takenOrigin
        self.lat = lat; self.lon = lon; self.locationOrigin = locationOrigin
        self.sha256 = sha256; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.addedAt = addedAt
    }
}

/// What a photo can hang on: an entity (person, place, thing, idea) or a memory.
public enum PhotoSubject: Sendable, Hashable { case entity(EntityID), memory(MemoryID) }

public enum PhotoRole: String, Codable, Sendable { case cover, attached }

/// A photo as one subject holds it.
public struct PlacedPhoto: Sendable, Equatable, Identifiable {
    public var photo: Photo
    public var role: PhotoRole
    public var id: PhotoID { photo.id }
    public var isCover: Bool { role == .cover }

    public init(photo: Photo, role: PhotoRole) { self.photo = photo; self.role = role }
}
