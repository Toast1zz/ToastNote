import SwiftUI

/// Floating-surface styling (spec §9.1). This is the only file that checks for macOS 26; everything else
/// asks for a `glassSurface` and gets Liquid Glass on 26 and a material with a hairline border before it.
extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
    }

    func floatingShadow() -> some View {
        shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}
