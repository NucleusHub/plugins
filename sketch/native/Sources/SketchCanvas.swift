import NucleusUI
import PencilKit
import SwiftUI
import UIKit

extension Paper {
    var color: UIColor {
        switch self {
        case .light, .grid: UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1)
        case .dark: UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        }
    }

    /// Ink colors adapt to this, so black ink stays readable on dark paper.
    var style: UIUserInterfaceStyle { self == .dark ? .dark : .light }

    var title: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .grid: "Grid"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .grid: "grid"
        }
    }

    func drawBackground(in rect: CGRect, context: CGContext) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
        guard self == .grid else { return }
        context.setStrokeColor(UIColor(red: 0.55, green: 0.6, blue: 0.75, alpha: 0.22).cgColor)
        context.setLineWidth(1)
        let step: CGFloat = 24
        var x = (rect.minX / step).rounded(.up) * step
        while x < rect.maxX { context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
        var y = (rect.minY / step).rounded(.up) * step
        while y < rect.maxY { context.move(to: CGPoint(x: rect.minX, y: y)); context.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
        context.strokePath()
    }
}

enum SketchExporter {
    /// The drawing trimmed to its bounds plus padding, rendered on its paper at 2× as PNG.
    @MainActor
    static func png(_ drawing: PKDrawing, paper: Paper) -> Data? {
        guard let rect = SketchGeometry.exportRect(drawingBounds: drawing.bounds) else { return nil }
        let scale = SketchGeometry.scale(for: rect)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: paper.style).performAsCurrent {
            ink = drawing.image(from: rect, scale: scale)
        }
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            paper.drawBackground(in: rect, context: ctx.cgContext)
            ink.draw(in: rect)
        }
        return image.pngData()
    }
}

/// PencilKit's canvas with the tool picker; fingers draw too.
struct CanvasView: UIViewRepresentable {
    let canvas: PKCanvasView
    let paper: Paper
    let onChange: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.delegate = context.coordinator
        canvas.alwaysBounceVertical = true
        canvas.contentSize = CGSize(width: 2000, height: 3000)
        context.coordinator.picker.addObserver(canvas)
        context.coordinator.picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.overrideUserInterfaceStyle = paper.style
        context.coordinator.picker.overrideUserInterfaceStyle = paper.style
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let picker = PKToolPicker()
        let onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { onChange() }
    }
}

/// The full-height drawing page: cancel, undo/redo, clear, paper, Done.
struct SketchSheet: View {
    let initial: PKDrawing?
    let initialPaper: Paper
    let onDone: (PKDrawing, Paper) async -> Void
    let onCancel: () -> Void
    @State private var canvas = PKCanvasView()
    @State private var paper: Paper
    @State private var isEmpty = true
    @State private var revision = 0
    @State private var saving = false

    init(initial: PKDrawing? = nil, paper: Paper = .light, onDone: @escaping (PKDrawing, Paper) async -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        initialPaper = paper
        self.onDone = onDone
        self.onCancel = onCancel
        _paper = State(initialValue: paper)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(paper.color).ignoresSafeArea()
            if paper == .grid {
                Canvas { context, size in
                    var path = Path()
                    for x in stride(from: 0, through: size.width, by: 24) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                    for y in stride(from: 0, through: size.height, by: 24) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                    context.stroke(path, with: .color(Color(red: 0.55, green: 0.6, blue: 0.75).opacity(0.22)), lineWidth: 1)
                }
                .ignoresSafeArea()
            }
            CanvasView(canvas: canvas, paper: paper) {
                isEmpty = canvas.drawing.strokes.isEmpty
                revision += 1
            }
            .ignoresSafeArea()
            toolbar
        }
        .environment(\.colorScheme, paper == .dark ? .dark : .light)
        .interactiveDismissDisabled(!isEmpty)
        .onAppear {
            if let initial { canvas.drawing = initial }
            isEmpty = canvas.drawing.strokes.isEmpty
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            GlassCircleButton("xmark", action: onCancel).accessibilityLabel("Cancel")
            Spacer()
            NucleusGlassContainer {
                HStack(spacing: 8) {
                    GlassCircleButton("arrow.uturn.backward") { canvas.undoManager?.undo(); refresh() }
                        .disabled(!(canvas.undoManager?.canUndo ?? false)).accessibilityLabel("Undo")
                    GlassCircleButton("arrow.uturn.forward") { canvas.undoManager?.redo(); refresh() }
                        .disabled(!(canvas.undoManager?.canRedo ?? false)).accessibilityLabel("Redo")
                    GlassCircleButton("trash") { canvas.drawing = PKDrawing(); refresh() }
                        .disabled(isEmpty).accessibilityLabel("Clear")
                    Menu {
                        Picker("Paper", selection: $paper) {
                            ForEach(Paper.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                        }
                    } label: {
                        Image(systemName: paper.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Nucleus.glyph)
                            .frame(width: 40, height: 40)
                            .nucleusGlass(in: Circle(), interactive: true)
                    }
                    .accessibilityLabel("Paper")
                }
            }
            Spacer()
            Button("Done") {
                saving = true
                Task { await onDone(canvas.drawing, paper) }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(Nucleus.primaryGradient))
            .opacity(isEmpty || saving ? 0.4 : 1)
            .disabled(isEmpty || saving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .id(revision)
    }

    private func refresh() {
        isEmpty = canvas.drawing.strokes.isEmpty
        revision += 1
    }
}
