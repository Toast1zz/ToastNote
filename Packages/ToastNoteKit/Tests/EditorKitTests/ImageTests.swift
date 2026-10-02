import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import EditorKit

private func makeVault() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tn-img-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

private func write(_ data: Data, to root: URL, _ path: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

/// Stands in for VaultKit's AttachmentStore, which EditorKit must not depend on.
private final class TestAttachments: AttachmentSaving, @unchecked Sendable {
    let root: URL
    private(set) var saved: [String] = []
    private(set) var imported: [URL] = []

    init(root: URL) { self.root = root }

    func save(imageData: Data, uti: UTType, date: Date) throws -> String {
        let path = "attachments/test-\(saved.count).png"
        try write(imageData, to: root, path)
        saved.append(path)
        return path
    }

    func importFile(_ url: URL, date: Date) throws -> String {
        let path = "attachments/imported-\(imported.count).\(url.pathExtension.lowercased())"
        try write(try Data(contentsOf: url), to: root, path)
        imported.append(url)
        return path
    }
}

@Suite struct ImageResolverTests {
    @Test func resolvesNoteRelativeThenVaultRelative() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 4, height: 4), to: root, "工作/near.png")
        try write(pngData(width: 4, height: 4), to: root, "attachments/far.png")

        let near = ImageResolver.resolve("near.png", notePath: "工作/周报.md", vaultRoot: root)
        #expect(near?.standardizedFileURL == root.appendingPathComponent("工作/near.png").standardizedFileURL)
        // Not next to the note, so the vault root is tried (Obsidian-style paths).
        let far = ImageResolver.resolve("attachments/far.png", notePath: "工作/周报.md", vaultRoot: root)
        #expect(far?.standardizedFileURL == root.appendingPathComponent("attachments/far.png").standardizedFileURL)
    }

    @Test func notePathAtVaultRootWorks() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 4, height: 4), to: root, "attachments/a.png")
        #expect(ImageResolver.resolve("attachments/a.png", notePath: "笔记.md", vaultRoot: root) != nil)
    }

    @Test func percentEncodedPathsAreDecoded() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 4, height: 4), to: root, "attachments/my pic.png")
        #expect(ImageResolver.resolve("attachments/my%20pic.png", notePath: "n.md", vaultRoot: root) != nil)
        #expect(ImageResolver.resolve("attachments/my pic.png", notePath: "n.md", vaultRoot: root) != nil)
    }

    @Test func remoteURLNotResolved() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ImageResolver.resolve("https://example.com/a.png", notePath: "n.md", vaultRoot: root) == nil)
        #expect(ImageResolver.resolve("http://example.com/a.png", notePath: "n.md", vaultRoot: root) == nil)
        #expect(ImageResolver.resolve("data:image/png;base64,AAAA", notePath: "n.md", vaultRoot: root) == nil)
    }

    @Test func missingAndEscapingPathsAreNil() throws {
        let root = try makeVault()
        let outside = try makeVault()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try write(pngData(width: 4, height: 4), to: outside, "secret.png")
        #expect(ImageResolver.resolve("nope.png", notePath: "n.md", vaultRoot: root) == nil)
        #expect(ImageResolver.resolve("../\(outside.lastPathComponent)/secret.png", notePath: "n.md", vaultRoot: root) == nil)
        #expect(ImageResolver.resolve("", notePath: "n.md", vaultRoot: root) == nil)
    }
}

@Suite struct ImageCacheTests {
    @Test func thumbnailRespectsWidth() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 400, height: 200), to: root, "big.png")
        let url = root.appendingPathComponent("big.png")
        let thumbnail = try #require(ImageCache.shared.thumbnail(for: url, maxPixelWidth: 100))
        let rep = try #require(thumbnail.representations.first)
        #expect(rep.pixelsWide <= 100)
        #expect(rep.pixelsWide >= 99)
        #expect(rep.pixelsHigh == 50)
    }

    @Test func smallImagesAreNotUpscaled() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 40, height: 20), to: root, "small.png")
        let thumbnail = try #require(ImageCache.shared.thumbnail(for: root.appendingPathComponent("small.png"), maxPixelWidth: 800))
        #expect(thumbnail.representations.first?.pixelsWide == 40)
    }

    @Test func secondRequestHitsTheCache() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 100, height: 100), to: root, "a.png")
        let url = root.appendingPathComponent("a.png")
        let first = ImageCache.shared.thumbnail(for: url, maxPixelWidth: 50)
        let second = ImageCache.shared.thumbnail(for: url, maxPixelWidth: 50)
        #expect(first != nil && first === second)
    }

    @Test func pixelSizeReadsHeaderOnly() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 320, height: 180), to: root, "a.png")
        #expect(ImageCache.shared.pixelSize(for: root.appendingPathComponent("a.png")) == CGSize(width: 320, height: 180))
        #expect(ImageCache.shared.pixelSize(for: root.appendingPathComponent("missing.png")) == nil)
    }

    @Test func unreadableFileGivesNil() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("not an image".utf8), to: root, "x.png")
        #expect(ImageCache.shared.thumbnail(for: root.appendingPathComponent("x.png"), maxPixelWidth: 100) == nil)
    }
}

@MainActor private var retainedWindows: [NSWindow] = []

@MainActor
private func makeView(_ text: String, vault: URL, notePath: String = "n.md") -> (MarkdownTextView, TestAttachments) {
    let view = MarkdownTextView(theme: .default)
    view.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = view
    retainedWindows.append(window)
    let attachments = TestAttachments(root: vault)
    view.vaultContext = (root: vault, notePath: notePath, attachments: attachments)
    view.markdown = text
    return (view, attachments)
}

@MainActor @Suite struct ImagePasteAndRenderTests {
    private func pasteboard(with items: [NSPasteboardWriting]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
        return pasteboard
    }

    @Test func pasteImageInsertsMarkdown() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let (view, attachments) = makeView("前文", vault: root)
        view.setSelectedRange(NSRange(location: 2, length: 0))
        let pb = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pb.clearContents()
        pb.setData(pngData(width: 30, height: 30), forType: .png)

        #expect(view.readSelection(from: pb))
        #expect(view.string.contains("![](attachments/"))
        let path = try #require(attachments.saved.first)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        #expect(view.string == "前文![](\(path))")
    }

    @Test func pasteTIFFScreenshot() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let (view, attachments) = makeView("", vault: root)
        let rep = NSBitmapImageRep(data: pngData(width: 20, height: 20))!
        let pb = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pb.clearContents()
        pb.setData(rep.representation(using: .tiff, properties: [:])!, forType: .tiff)
        #expect(view.readSelection(from: pb))
        #expect(attachments.saved.count == 1)
    }

    @Test func pasteImageFileImportsIt() throws {
        let root = try makeVault()
        let elsewhere = try makeVault()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        try write(pngData(width: 10, height: 10), to: elsewhere, "照片.png")
        let file = elsewhere.appendingPathComponent("照片.png")
        let (view, attachments) = makeView("", vault: root)
        let pb = pasteboard(with: [file as NSURL])
        #expect(view.readSelection(from: pb))
        #expect(attachments.imported == [file])
        #expect(view.string.hasPrefix("![](attachments/imported-0.png"))
    }

    @Test func nonImageFilesAreNotImported() throws {
        let root = try makeVault()
        let elsewhere = try makeVault()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        try write(Data("hello".utf8), to: elsewhere, "note.txt")
        let (view, attachments) = makeView("", vault: root)
        _ = view.readSelection(from: pasteboard(with: [elsewhere.appendingPathComponent("note.txt") as NSURL]))
        #expect(attachments.imported.isEmpty)
    }

    @Test func plainTextStillPastes() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let (view, _) = makeView("", vault: root)
        let pb = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pb.clearContents()
        pb.setString("纯文本", forType: .string)
        #expect(view.readSelection(from: pb))
        #expect(view.string == "纯文本")
    }

    @Test func imageLineReservesSpaceForTheImage() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 400, height: 300), to: root, "attachments/p.png")
        let (view, _) = makeView("![](attachments/p.png)\n\n正文", vault: root)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))  // caret in the other block
        let style = view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        // The line is as tall as the picture (shown at half its pixel size on a 2x display, at most the text width).
        #expect((style?.minimumLineHeight ?? 0) > 100)
        #expect(style?.minimumLineHeight == style?.maximumLineHeight)
    }

    @Test func imageLineIsResizedWhenTheWindowChangesWidth() throws {
        // The view may be laid out at zero width when the note is first set; the picture's line must follow the real width.
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 2000, height: 1000), to: root, "attachments/wide.png")
        let (view, _) = makeView("![](attachments/wide.png)\n\n正文", vault: root)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.setFrameSize(NSSize(width: 300, height: 500))
        let narrow = (view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.minimumLineHeight ?? 0
        view.setFrameSize(NSSize(width: 1400, height: 500))
        let wide = (view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.minimumLineHeight ?? 0
        #expect(narrow > 0)
        #expect(wide > narrow, "narrow \(narrow), wide \(wide)")
    }

    @Test func activeImageLineShowsSourceAndReservesNothing() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(pngData(width: 400, height: 300), to: root, "attachments/p.png")
        let (view, _) = makeView("![](attachments/p.png)\n\n正文", vault: root)
        view.setSelectedRange(NSRange(location: 3, length: 0))
        let style = view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.maximumLineHeight ?? 0) < 40)
    }

    @Test func missingImageStaysAsText() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let (view, _) = makeView("![](attachments/gone.png)\n\n正文", vault: root)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: 0)
        #expect(!view.layoutManager!.propertyForGlyph(at: glyph).contains(.null))
    }
}

@Suite struct StylerImageTests {
    private func style(_ text: String, resolves: Bool) -> StyleResult {
        let blocks = BlockParser.parse(text)
        return MarkdownStyler.style(blocks: blocks, text: text as NSString, active: IndexSet(), concealAll: false, resolveImage: { _ in resolves })
    }

    @Test func resolvedImageLineKeepsOneInvisibleCharacterSoItHasALineToStandIn() {
        // A paragraph made only of hidden glyphs gets no line fragment of its own, so the "!" stays (clear).
        let result = style("![图](a.png)", resolves: true)
        #expect(result.hidden == [NSRange(location: 1, length: 10)])
        #expect(result.runs.contains { $0.style.role == .imagePlaceholder && $0.range == NSRange(location: 0, length: 1) })
        #expect(result.decorations.contains(.image(source: "a.png", lineRange: NSRange(location: 0, length: 11))))
    }

    @Test func imageInsideTextStaysVisible() {
        let result = style("见 ![图](a.png) 图", resolves: true)
        #expect(result.hidden.isEmpty)
        #expect(!result.decorations.contains { if case .image = $0 { true } else { false } })
    }

    @Test func unresolvedImageStaysVisibleAsMutedText() {
        let result = style("![图](a.png)", resolves: false)
        #expect(result.hidden.isEmpty)
        #expect(!result.decorations.contains { if case .image = $0 { true } else { false } })
        #expect(result.runs.contains { $0.style.role == .marker && $0.range == NSRange(location: 0, length: 11) })
    }
}
