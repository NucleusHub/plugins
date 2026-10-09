import AVFoundation
import Foundation
import Observation

/// Records AAC (m4a) with a live level meter; pause and resume; stops itself at 30 minutes.
@MainActor @Observable
final class Recorder {
    enum State: Equatable { case idle, recording, paused, finished, denied, failed }

    private(set) var state = State.idle
    private(set) var elapsed: TimeInterval = 0
    /// Recent levels 0…1, oldest first.
    private(set) var levels: [Float] = Array(repeating: 0, count: Recorder.levelCount)
    static let levelCount = 48

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored let url = FileManager.default.temporaryDirectory.appending(path: "voice-memo-\(UUID().uuidString).m4a")

    /// It stopped itself at the 30-minute limit; another `record()` would start over.
    private(set) var atLimit = false

    var hasAudio: Bool { elapsed > 0.3 && (state == .paused || state == .recording || state == .finished) }

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else { state = .denied; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: AudioMath.maxDuration) else { state = .failed; return }
            self.recorder = recorder
            state = .recording
            tick()
        } catch {
            state = .failed
        }
    }

    func pause() {
        recorder?.pause()
        state = .paused
    }

    func resume() {
        guard !atLimit, recorder?.record() == true else { return }
        state = .recording
        tick()
    }

    /// Stops and returns the recording's bytes.
    func finish() -> Data? {
        recorder?.stop()
        ticker?.cancel()
        state = .finished
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return try? Data(contentsOf: url)
    }

    func discard() {
        recorder?.stop()
        recorder?.deleteRecording()
        ticker?.cancel()
        try? FileManager.default.removeItem(at: url)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
        elapsed = 0
    }

    private func tick() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self, let recorder = self.recorder else { return }
                if !recorder.isRecording {
                    // `record(forDuration:)` ran out: 30 minutes.
                    if self.state == .recording {
                        self.atLimit = true
                        self.state = .paused
                    }
                    return
                }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                self.levels.removeFirst()
                self.levels.append(AudioMath.level(decibels: recorder.averagePower(forChannel: 0)))
            }
        }
    }
}
