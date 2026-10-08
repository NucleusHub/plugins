import NucleusUI
import SwiftUI

/// A title's poster, or a tinted tile with its initial when there's none or it won't load.
struct Poster: View {
    let url: String?
    let title: String
    let type: String
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let url, let link = URL(string: url) {
                    AsyncImage(url: link, transaction: Transaction(animation: NucleusMotion.quick)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [hue.opacity(0.85), hue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: geo.size.width * 0.06) {
                    Text(verbatim: initial)
                        .font(.system(size: geo.size.width * 0.38, weight: .bold, design: .rounded))
                    Image(systemName: type == "movie" ? "film" : "tv")
                        .font(.system(size: geo.size.width * 0.14, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
            }
        }
    }

    private var initial: String { title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "?" }

    /// Stable per title, so a placeholder looks the same everywhere.
    private var hue: Color {
        let sum = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.55, brightness: 0.7)
    }
}
