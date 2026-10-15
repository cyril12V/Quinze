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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` with a voice for `locale` (e.g. "en-GB"). Uses a slightly slower rate when `slow`.
    func speak(_ text: String, locale: String, slow: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.88)
        utterance.pitchMultiplier = 1.0
        isSpeaking = true
        synthesizer.speak(utterance)
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
