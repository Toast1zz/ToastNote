import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor private var retainedWindows: [NSWindow] = []

@MainActor @Suite struct BlockLabelDrawingTests {
    private func render(_ view: MarkdownTextView) -> NSBitmapImageRep? {
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        // The view sizes itself to its text; give it a fixed height so there is something to render.
        view.setFrameSize(NSSize(width: 600, height: 300))
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Number of clearly non-white pixels in the left gutter (x < `width`).
    private func inkInGutter(_ rep: NSBitmapImageRep, width: Int) -> Int {
        guard let data = rep.bitmapData else { return 0 }
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<min(width, rep.pixelsWide) {
                let pixel = data + y * rep.bytesPerRow + x * (rep.bitsPerPixel / 8)
                let (r, g, b, a) = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]), Int(pixel[3]))
                if a > 128, r + g + b < 700 { count += 1 }
            }
        }
        return count
    }

    private func makeView() -> MarkdownTextView {
        let view = MarkdownTextView(theme: .default, concealAll: true)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.fixedHorizontalInset = 80
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        retainedWindows.append(window)
        view.markdown = "# 标题\n\n正文一段"
        return view
    }

    @Test func labelsAndBarsAreDrawnInTheGutter() throws {
        let view = makeView()
        let plain = try #require(render(view))
        let before = inkInGutter(plain, width: 76)
        view.blockLabels = [0: "变为标题"]
        let labelled = try #require(render(view))
        let after = inkInGutter(labelled, width: 76)
        #expect(after > before, "gutter ink before \(before), after \(after)")
    }
}
