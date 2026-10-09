import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit

/// Bars of levels, the played part in the accent.
struct WaveformBars: View {
    let levels: [Float]
    var progress: Double = 1
    var tint: Color = Nucleus.accent

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let gap: CGFloat = 3
            let width = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1)
            HStack(alignment: .center, spacing: gap) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(Double(index) / Double(count) < progress ? tint : Nucleus.secondaryText.opacity(0.35))
                        .frame(width: width, height: max(CGFloat(level) * geo.size.height, 3))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// The recorder: time, a live waveform, record/pause, discard and done.
struct RecorderSheet: View {
    let onDone: (Data) async -> Void
    let onCancel: () -> Void
    @State var recorder = Recorder()
    @State private var confirmDiscard = false
    @State private var saving = false

    var body: some View {
        NucleusSheetPage("Voice memo", confirmTitle: "Done", canConfirm: recorder.hasAudio && !saving,
                         onCancel: cancel, onConfirm: done) {
            VStack(spacing: 28) {
                Text(verbatim: AudioMath.clock(recorder.elapsed))
                    .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Nucleus.primaryText)
                    .contentTransition(.numericText())
                WaveformBars(levels: recorder.levels, tint: recorder.state == .recording ? Nucleus.danger : Nucleus.secondaryText)
                    .frame(height: 90)
                    .padding(.horizontal, 8)
                Text(status)
                    .font(.system(size: 15))
                    .foregroundStyle(recorder.state == .denied || recorder.state == .failed ? Nucleus.danger : Nucleus.secondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: 40) {
                    GlassCircleButton("trash", size: 52, tint: Nucleus.danger) { confirmDiscard = true }
                        .disabled(!recorder.hasAudio)
                        .opacity(recorder.hasAudio ? 1 : 0.35)
                        .accessibilityLabel("Discard")
                    recordButton
                    Color.clear.frame(width: 52, height: 52)
                }
                if recorder.state == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(NucleusSecondaryButtonStyle())
                }
            }
            .padding(.top, 40)
        }
        .interactiveDismissDisabled(recorder.hasAudio)
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { recorder.discard() }
        }
    }

    private var status: LocalizedStringKey {
        switch recorder.state {
        case .idle: "Tap to record. Up to 30 minutes."
        case .recording: "Recording…"
        case .paused: recorder.atLimit ? "That's the 30-minute limit. Tap Done to keep it." : "Paused"
        case .finished: "Saving…"
        case .denied: "Notes needs the microphone to record. You can allow it in Settings."
        case .failed: "Recording couldn't start. Try again."
        }
    }

    private var recordButton: some View {
        Button {
            Haptics.tap()
            switch recorder.state {
            case .idle, .failed: Task { await recorder.start() }
            case .recording: recorder.pause()
            case .paused: recorder.resume()
            case .finished, .denied: break
            }
        } label: {
            ZStack {
                Circle().strokeBorder(Nucleus.danger.opacity(0.35), lineWidth: 4).frame(width: 84, height: 84)
                if recorder.state == .recording {
                    Image(systemName: "pause.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 68, height: 68).background(Circle().fill(Nucleus.danger))
                } else {
                    Circle().fill(Nucleus.danger).frame(width: 64, height: 64)
                }
            }
        }
        .buttonStyle(NucleusPressStyle())
        .disabled(recorder.atLimit || recorder.state == .denied)
        .accessibilityLabel(recorder.state == .recording ? "Pause" : "Record")
    }

    private func cancel() {
        if recorder.hasAudio { confirmDiscard = true } else { recorder.discard(); onCancel() }
    }

    private func done() {
        guard let data = recorder.finish() else { return }
        saving = true
        Task { await onDone(data) }
    }
}

/// One recording: play/pause, a waveform scrubber, speed, and its transcript.
struct PlayerCard: View {
    let attachment: Attachment
    let host: any NotesHost
    let transcript: String?
    let save: (String) -> Void
    let insert: (String) -> Void
    @State private var playback = Playback()
    @State private var bars: [Float] = Array(repeating: 0.06, count: 40)
    @State private var data: Data?
    @State private var transcribing = false
    @State private var problem: LocalizedStringKey?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Nucleus.primaryGradient))
                }
                .buttonStyle(NucleusPressStyle())
                .disabled(!playback.isLoaded)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                VStack(spacing: 4) {
                    WaveformBars(levels: bars, progress: playback.duration > 0 ? playback.currentTime / playback.duration : 0)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            scrub(drag.location.x)
                        })
                        .overlay(GeometryReader { geo in Color.clear.preference(key: WidthKey.self, value: geo.size.width) })
                        .onPreferenceChange(WidthKey.self) { width = $0 }
                    HStack {
                        Text(verbatim: AudioMath.clock(playback.currentTime))
                        Spacer()
                        Text(verbatim: AudioMath.clock(playback.duration))
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Nucleus.secondaryText)
                }
                Button { playback.cycleRate() } label: {
                    Text(verbatim: AudioMath.rateLabel(playback.rate))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Nucleus.accent)
                        .frame(width: 44, height: 30)
                        .background(Capsule().fill(Nucleus.accent.opacity(0.12)))
                }
                .buttonStyle(NucleusPressStyle())
                .accessibilityLabel("Playback speed")
            }
            transcriptView
        }
        .padding(14)
        .task(id: attachment.id) { await load() }
    }

    @State private var width: CGFloat = 1

    private func scrub(_ x: CGFloat) {
        playback.seek(to: Double(x / max(width, 1)))
    }

    @ViewBuilder
    private var transcriptView: some View {
        if let transcript {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: transcript)
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { withAnimation(NucleusMotion.quick) { expanded.toggle() } }
                HStack(spacing: 10) {
                    pill("Insert transcript", icon: "text.quote") { insert(transcript) }
                    pill("Copy", icon: "doc.on.doc") {
                        UIPasteboard.general.string = transcript
                        host.show(String(localized: "Transcript copied"), icon: "doc.on.doc")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Nucleus.well))
        } else if transcribing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing on this device…").font(.system(size: 14)).foregroundStyle(Nucleus.secondaryText)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let problem {
                    Text(problem).font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText)
                }
                pill("Transcribe", icon: "text.bubble") { Task { await transcribe() } }
            }
        }
    }

    private func pill(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Nucleus.accent)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(Nucleus.accent.opacity(0.12)))
        }
        .buttonStyle(NucleusPressStyle())
    }

    private func load() async {
        guard data == nil, let loaded = try? await host.attachmentData(attachment) else { return }
        data = loaded
        playback.load(loaded)
        let peaks = await AudioFile.peaks(of: loaded, count: 40)
        if !peaks.isEmpty { bars = peaks }
        // Already allowed: transcribe without asking, once per recording.
        if transcript == nil, Transcriber.isAuthorized, !PendingMemos.shared.failed.contains(attachment.id) { await transcribe() }
    }

    private func transcribe() async {
        guard let data, !transcribing else { return }
        transcribing = true
        defer { transcribing = false }
        do {
            save(try await Transcriber.transcribe(data))
            problem = nil
        } catch Transcriber.Failure.denied {
            problem = "To get transcripts, allow Speech Recognition for Notes in Settings."
        } catch Transcriber.Failure.nothingHeard {
            PendingMemos.shared.failed.insert(attachment.id)
            problem = "No speech was heard in this recording."
        } catch {
            PendingMemos.shared.failed.insert(attachment.id)
            problem = "Couldn't transcribe this recording right now."
        }
    }
}

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
