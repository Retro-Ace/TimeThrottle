import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public struct VoiceGuidanceSettings: Codable, Equatable, Sendable {
    public var selectedVoiceIdentifier: String?
    public var speechRate: Float
    public var volume: Float
    public var isMuted: Bool

    public init(
        selectedVoiceIdentifier: String? = VoiceGuidanceVoiceCatalog.preferredDefaultVoiceIdentifier(),
        speechRate: Float = Self.defaultSpeechRate,
        volume: Float = 0.92,
        isMuted: Bool = false
    ) {
        self.selectedVoiceIdentifier = selectedVoiceIdentifier
        self.speechRate = min(max(speechRate, 0.36), 0.58)
        self.volume = min(max(volume, 0), 1)
        self.isMuted = isMuted
    }

    public static let defaultSpeechRate: Float = 0.46
}

public struct VoiceGuidanceVoiceOption: Identifiable, Codable, Equatable, Sendable {
    public var id: String { identifier }
    public var identifier: String
    public var name: String
    public var language: String
    public var qualityRank: Int

    public init(identifier: String, name: String, language: String, qualityRank: Int) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.qualityRank = qualityRank
    }
}

public enum VoiceGuidanceVoiceCatalog {
    public static func availableEnglishVoices() -> [VoiceGuidanceVoiceOption] {
        #if canImport(AVFoundation)
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .sorted { left, right in
                if left.quality.rawValue != right.quality.rawValue {
                    return left.quality.rawValue > right.quality.rawValue
                }

                if preferredLanguageScore(left.language) != preferredLanguageScore(right.language) {
                    return preferredLanguageScore(left.language) > preferredLanguageScore(right.language)
                }

                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            .map {
                VoiceGuidanceVoiceOption(
                    identifier: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    qualityRank: $0.quality.rawValue
                )
            }
        #else
        []
        #endif
    }

    public static func bestAvailableEnglishVoiceIdentifier() -> String? {
        availableEnglishVoices().first?.identifier
    }

    public static func preferredDefaultVoiceIdentifier() -> String? {
        let voices = availableEnglishVoices()
        return danielVoiceIdentifier(in: voices) ?? voices.first?.identifier
    }

    public static func danielVoiceIdentifier(in voices: [VoiceGuidanceVoiceOption]) -> String? {
        let englishDanielByName = voices.first {
            isEnglishLanguage($0.language) && $0.name.localizedCaseInsensitiveContains("Daniel")
        }
        if let englishDanielByName {
            return englishDanielByName.identifier
        }

        let englishDanielByIdentifier = voices.first {
            isEnglishLanguage($0.language) && $0.identifier.localizedCaseInsensitiveContains("Daniel")
        }
        if let englishDanielByIdentifier {
            return englishDanielByIdentifier.identifier
        }

        return voices.first {
            $0.name.localizedCaseInsensitiveContains("Daniel") ||
                $0.identifier.localizedCaseInsensitiveContains("Daniel")
        }?.identifier
    }

    private static func preferredLanguageScore(_ language: String) -> Int {
        let normalized = language.lowercased()
        if normalized == "en-us" { return 3 }
        if normalized.hasPrefix("en-") { return 2 }
        if normalized.hasPrefix("en") { return 1 }
        return 0
    }

    private static func isEnglishLanguage(_ language: String) -> Bool {
        language.lowercased().hasPrefix("en")
    }
}
