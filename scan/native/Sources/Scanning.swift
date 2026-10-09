import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit
import Vision
import VisionKit

/// One scanned page, ready to store.
struct ScannedPage: Sendable {
    let jpeg: Data
    let text: String
}

enum Scanner {
    @MainActor static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// On-device text recognition, accurate, English and Czech.
    static func recognize(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "cs-CZ"]
            let handler = VNImageRequestHandler(cgImage: image)
            guard (try? handler.perform([request])) != nil else { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return ScanTexts.clean(lines)
        }.value
    }

    /// The page downscaled to 2560 px and JPEG'd like the app's photos, plus its text.
    static func prepare(_ image: UIImage) async -> ScannedPage? {
        let size = ScanTexts.fitted(CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8), let cg = scaled.cgImage else { return nil }
        return ScannedPage(jpeg: jpeg, text: await recognize(cg))
    }
}

/// VisionKit's document camera.
struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onCancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onCancel() }
    }
}

/// The camera, then a short "Reading text" while pages are prepared.
struct ScanSheet: View {
    let onPages: ([ScannedPage]) async -> Void
    let onCancel: () -> Void
    @State private var progress: (done: Int, total: Int)?

    var body: some View {
        ZStack {
            if let progress {
                ReadingText(done: progress.done, total: progress.total)
            } else {
                DocumentCamera(onFinish: { images in Task { await process(images) } }, onCancel: onCancel)
                    .ignoresSafeArea()
            }
        }
        .interactiveDismissDisabled(progress != nil)
    }

    private func process(_ images: [UIImage]) async {
        guard !images.isEmpty else { return onCancel() }
        progress = (0, images.count)
        var pages: [ScannedPage] = []
        for image in images {
            if let page = await Scanner.prepare(image) { pages.append(page) }
            progress = (pages.count, images.count)
        }
        await onPages(pages)
    }
}

struct ReadingText: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 16) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                Text("Reading text…")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                Text("Page \(min(done + 1, total)) of \(total), on this device")
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.secondaryText)
            }
        }
    }
}
