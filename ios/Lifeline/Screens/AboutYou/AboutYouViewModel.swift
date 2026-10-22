import Foundation
import LifelineKit

@MainActor
@Observable
final class AboutYouViewModel {
    enum Mode { case firstOpen, settings }

    var name = ""
    var hasBirthday = false
    var birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var birthPlace = ""
    var freeText = ""
    private(set) var error: String?

    let mode: Mode
    private let repository: ProfileRepository
    private let onDone: () -> Void

    init(profile: ProfileRepository, mode: Mode, onDone: @escaping () -> Void) {
        self.repository = profile
        self.mode = mode
        self.onDone = onDone
        if let existing = try? profile.fetch() {
            name = existing.displayName ?? ""
            hasBirthday = existing.birthDate != nil
            birthday = existing.birthDate ?? birthday
            birthPlace = existing.birthPlaceText ?? ""
            freeText = existing.freeText ?? ""
        }
    }

    /// Saves an empty profile so first open does not repeat.
    func skip() { persist(Profile(displayName: nil, birthDate: nil, birthPlaceText: nil, freeText: nil, updatedAt: .now)) }

    func save() {
        persist(Profile(displayName: blankToNil(name), birthDate: hasBirthday ? birthday : nil,
                        birthPlaceText: blankToNil(birthPlace), freeText: blankToNil(freeText), updatedAt: .now))
    }

    private func persist(_ profile: Profile) {
        do {
            try repository.save(profile)
            onDone()
        } catch {
            self.error = "Could not save: \(error.localizedDescription)"
        }
    }

    private func blankToNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
