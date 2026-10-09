import AVFoundation
import Foundation
import Observation
import Speech

/// Plays one recording; starting another stops the one before.
@MainActor @Observable
final class Playback {
    @ObservationIgnored private static weak var playing: Playback?

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func load(_ data: Data) {
        guard player == nil, let player = try? AVAudioPlayer(data: data) else { return }
        player.enableRate = true
        player.prepareToPlay()
        self.player = player
        duration = player.duration
    }

    var isLoaded: Bool { player != nil }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
            return
        }
        if Playback.playing !== self { Playback.playing?.stopForOther() }
        Playback.playing = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        player.rate = rate
        player.play()
        isPlaying = true
        tick()
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = min(max(fraction, 0), 1) * player.duration
        currentTime = player.currentTime
    }

    func cycleRate() {
        rate = AudioMath.nextRate(after: rate)
        player?.rate = rate
    }

    func stop() {
        player?.stop()
        isPlaying = false
        ticker?.cancel()
    }

    private func stopForOther() { stop() }

    private func tick() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    if player.currentTime == 0 { self.currentTime = self.duration }
                    return
                }
            }
        }
    }
}

enum AudioFile {
    /// Peak levels in `count` stretches of the file, 0…1; reads a slice of each so long recordings stay cheap.
    static func peaks(of data: Data, count: Int) async -> [Float] {
        await Task.detached(priority: .utility) {
            let url = FileManager.default.temporaryDirectory.appending(path: "peaks-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            guard (try? data.write(to: url)) != nil, let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { return [] }
            let length = file.length
            guard length > 0 else { return [] }
            var peaks: [Float] = []
            for index in 0..<count {
                file.framePosition = length * AVAudioFramePosition(index) / AVAudioFramePosition(count)
                buffer.frameLength = 0
                guard (try? file.read(into: buffer, frameCount: 4096)) != nil, let samples = buffer.floatChannelData?[0] else {
                    peaks.append(0)
                    continue
                }
                var peak: Float = 0
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
                peaks.append(peak)
            }
            return AudioMath.normalizedBars(peaks)
        }.value
    }
}

/// On-device speech to text (the server only when the device can't, for its language).
enum Transcriber {
    enum Failure: Error { case denied, unavailable, nothingHeard }

    static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var isDenied: Bool { [.denied, .restricted].contains(SFSpeechRecognizer.authorizationStatus()) }

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    static func transcribe(_ data: Data) async throws -> String {
        if !isAuthorized {
            guard await requestAccess() else { throw Failure.denied }
        }
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        let locale = Transcripts.locale(current: .current, supported: supported)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw Failure.unavailable }
        let url = FileManager.default.temporaryDirectory.appending(path: "transcribe-\(UUID().uuidString).m4a")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let text: String = try await withCheckedThrowingContinuation { continuation in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    done = true
                    continuation.resume(throwing: error)
                }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.nothingHeard }
        return trimmed
    }
}
