import SwiftUI

/// Branded hero surface: gradient + decorative shapes (+ optional city skyline).
struct HeroBackground<Content: View>: View {
    var skyline: Bool = false
    var gradient: LinearGradient = Brand.hero
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Rectangle().fill(gradient)
            Canvas { ctx, size in drawHeroDecor(ctx, size, skyline: skyline) }
            content()
        }
        .ignoresSafeArea()
    }
}

private let skylineHeights: [CGFloat] = [0.10, 0.17, 0.12, 0.24, 0.15, 0.20, 0.11, 0.27, 0.14, 0.19, 0.09, 0.16]

private func drawHeroDecor(_ ctx: GraphicsContext, _ size: CGSize, skyline: Bool) {
    let w = size.width, h = size.height
    func glow(_ color: Color, _ center: CGPoint, _ radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color, .clear]), center: center, startRadius: 0, endRadius: radius))
    }
    glow(Brand.teal.opacity(0.40), CGPoint(x: w * 0.92, y: h * 0.05), w * 0.75)
    glow(Brand.amber.opacity(0.18), CGPoint(x: 0, y: h * 0.85), w * 0.6)
    let ringCenter = CGPoint(x: w, y: h * 0.18)
    for i in 1...4 {
        let r = w * (0.20 + CGFloat(i) * 0.14)
        ctx.stroke(Path(ellipseIn: CGRect(x: ringCenter.x - r, y: ringCenter.y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(0.07)), lineWidth: 1.5)
    }
    let r2 = w * 0.22
    ctx.fill(Path(ellipseIn: CGRect(x: w * 0.05 - r2, y: h * 0.30 - r2, width: r2 * 2, height: r2 * 2)), with: .color(.white.opacity(0.05)))
    if skyline { drawSkyline(ctx, size, scale: 1) }
}

private func drawSkyline(_ ctx: GraphicsContext, _ size: CGSize, scale: CGFloat) {
    let w = size.width, h = size.height
    let count = skylineHeights.count
    let bw = w / CGFloat(count)
    for (i, fraction) in skylineHeights.enumerated() {
        let bh = h * fraction * scale
        let left = CGFloat(i) * bw
        let rect = CGRect(x: left + bw * 0.06, y: h - bh, width: bw * 0.88, height: bh + 8)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.075)))
        let rows = max(Int(bh / 22), 1)
        for r in 0..<rows {
            for c in 0..<2 where (i * 7 + r * 3 + c * 5) % 3 == 0 {
                let win = CGRect(x: left + bw * (0.25 + CGFloat(c) * 0.30), y: h - bh + 10 + CGFloat(r) * 22, width: bw * 0.14, height: 8)
                ctx.fill(Path(roundedRect: win, cornerRadius: 2), with: .color(Brand.amber.opacity(0.35)))
            }
        }
    }
}

/// Decorative city skyline strip, sits at the bottom edge of its bounds.
struct SkylineStrip: View {
    var body: some View {
        Canvas { ctx, size in drawSkyline(ctx, size, scale: 3.4) }
    }
}

/// The bank logo tile.
struct AppLogo: View {
    var size: CGFloat = 56
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "building.columns.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(Brand.royal)
            )
    }
}

/// Rounded tinted tile holding an SF Symbol, used in lists and cards.
struct IconBadge: View {
    var systemName: String
    var tint: Color = Theme.primary
    var size: CGFloat = 44
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(Image(systemName: systemName).font(.system(size: size * 0.45, weight: .semibold)).foregroundColor(tint))
    }
}

/// Circle with an initial.
struct Avatar: View {
    var name: String
    var size: CGFloat = 44
    var tint: Color = Theme.primary
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}

/// Animated loading placeholder.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.6
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [Theme.surfaceHigh, Color.white.opacity(0.9), Theme.surfaceHigh],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 1.6)
                        .offset(x: geo.size.width * phase)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 0.8 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

struct PrimaryButton: View {
    var text: String
    var icon: String? = nil
    var loading: Bool = false
    var enabled: Bool = true
    var fullWidth: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(text).font(AppFont.labelLarge)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 54)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(enabled ? Theme.primary : Theme.primary.opacity(0.4)))
        }
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    var text: String
    var icon: String? = nil
    var enabled: Bool = true
    var fullWidth: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(text).font(AppFont.labelLarge)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 54)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .foregroundColor(enabled ? Theme.primary : Theme.onSurfaceVariant)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(enabled ? Theme.primary.opacity(0.5) : Theme.outlineVariant, lineWidth: 1.5))
        }
        .disabled(!enabled)
    }
}
