import Testing
@testable import LifelineKit

struct VoicePickerTests {
    private func voice(_ id: String, _ language: String, _ quality: VoiceInfo.Quality) -> VoiceInfo {
        VoiceInfo(identifier: id, language: language, quality: quality)
    }

    @Test func premiumBeatsEnhancedBeatsDefault() {
        let compact = voice("us.compact", "en-US", .default)
        let enhanced = voice("us.enhanced", "en-US", .enhanced)
        let premium = voice("us.premium", "en-US", .premium)
        #expect(VoicePicker.best([compact, enhanced, premium]) == premium)
        #expect(VoicePicker.best([compact, enhanced]) == enhanced)
        #expect(VoicePicker.best([compact]) == compact)
    }

    @Test func aUSVoiceBeatsOtherEnglish() {
        let british = voice("gb.premium", "en-GB", .premium)
        let australian = voice("au.enhanced", "en-AU", .enhanced)
        let american = voice("us.compact", "en-US", .default)
        let french = voice("fr.premium", "fr-FR", .premium)
        #expect(VoicePicker.best([british, american, french]) == american)
        #expect(VoicePicker.best([australian, british, french]) == british, "the best other English voice")
        #expect(VoicePicker.best([french]) == nil, "only English voices")
        #expect(VoicePicker.best([]) == nil)
    }

    @Test func onlyCompactWhenNoEnhancedOrPremium() {
        #expect(VoicePicker.onlyCompact([voice("us.compact", "en-US", .default), voice("gb.compact", "en-GB", .default)]))
        #expect(VoicePicker.onlyCompact([voice("fr.premium", "fr-FR", .premium)]), "a French voice cannot speak the English lines")
        #expect(VoicePicker.onlyCompact([]))
        #expect(!VoicePicker.onlyCompact([voice("us.compact", "en-US", .default), voice("us.enhanced", "en-US", .enhanced)]))
    }
}
