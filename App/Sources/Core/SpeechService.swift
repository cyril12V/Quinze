import Foundation
import Observation
import AVFoundation

// CONTRACT FILE — owned by the "services" workstream (B1).
// Native text-to-speech (AVSpeechSynthesizer) for V1; designed so validated recordings can be
// plugged in later (§11.4).

@MainActor
@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    /// Voice chosen in the settings per language ("en", "ar", "fr") → AVSpeechSynthesisVoice identifier.
    @ObservationIgnored var preferredVoices: [String: String] = [:]
    /// AVSpeechUtterance rate for normal speech (slow = 70 % of it).
    @ObservationIgnored var rate: Float = 0.46

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` with the best voice for `locale` (e.g. "en-GB"). Uses a slower rate when `slow`.
    /// Arabic text is always read by an Arabic voice and French text by a French one, whatever `locale` says.
    func speak(_ text: String, locale: String, slow: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: trimmed)
        let effectiveLocale = trimmed.containsArabic ? "ar-SA" : locale
        let language = String(effectiveLocale.prefix(2))
        utterance.voice = Self.bestVoice(for: effectiveLocale, preferred: preferredVoices[language])
        utterance.rate = min(max(rate * (slow ? 0.7 : 1), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = 1.0
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: Voices

    /// Female voices that sound natural even in their basic (compact) version, best first.
    private static let pleasantNames = ["Ava", "Zoe", "Serena", "Samantha", "Allison", "Susan", "Kate", "Stephanie",
                                        "Martha", "Karen", "Moira", "Tessa", "Amélie", "Audrey", "Aurélie", "Marie",
                                        "Laila", "Mariam", "Hala", "Majed", "Tarik"]

    /// Voices of a language ("en", "ar", "fr"), best first: Premium, then Enhanced, then the rest;
    /// novelty voices (Bells, Zarvox…) and the robotic Eloquence voices are left out.
    static func voices(language: String) -> [AVSpeechSynthesisVoice] {
        let robotic: Set<String> = ["Eddy", "Flo", "Grandma", "Grandpa", "Reed", "Rocko", "Sandy", "Shelley"]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !robotic.contains($0.name) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return rank(lhs.name) < rank(rhs.name)
            }
    }

    private static func rank(_ name: String) -> Int {
        pleasantNames.firstIndex { name.hasPrefix($0) } ?? pleasantNames.count
    }

    /// The chosen voice when it still exists, else the best installed voice, preferring the exact locale
    /// at equal quality.
    static func bestVoice(for locale: String, preferred identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        let language = String(locale.prefix(2))
        let candidates = voices(language: language)
        guard let topQuality = candidates.first?.quality else { return AVSpeechSynthesisVoice(language: locale) }
        let best = candidates.filter { $0.quality == topQuality }
        return best.first { $0.language == locale } ?? best.first
    }

    /// "Premium", "Améliorée" or "Standard".
    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Améliorée"
        default: return "Standard"
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
        deactivateAudioSession()
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Delegate callbacks arrive off the main actor.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speechEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speechEnded() }
    }

    private func speechEnded() {
        // A newer utterance may already be queued (tap on another word): only reset when idle.
        if !synthesizer.isSpeaking {
            isSpeaking = false
            deactivateAudioSession()
        }
    }
}
