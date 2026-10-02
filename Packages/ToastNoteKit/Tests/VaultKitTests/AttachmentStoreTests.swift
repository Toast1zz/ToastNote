import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import VaultKit

private func samplePNG(width: Int = 40, height: Int = 20) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

private func sampleTIFF() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 30, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .tiff, properties: [:])!
}

private let pngMagic = Data([0x89, 0x50, 0x4E, 0x47])

@Suite struct AttachmentStoreTests {
    @Test func savesPNGWithPattern() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AttachmentStore(vaultRoot: root)
        let path = try store.save(imageData: samplePNG(), uti: .png)
        #expect(path.range(of: #"^attachments/\d{8}-\d{6}-[a-z0-9]{4}\.png$"#, options: .regularExpression) != nil, "got \(path)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
    }

    @Test func fileNameUsesTheGivenDate() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 2
        components.hour = 14; components.minute = 5; components.second = 9
        let date = Calendar.current.date(from: components)!
        let path = try AttachmentStore(vaultRoot: root).save(imageData: samplePNG(), uti: .png, date: date)
        #expect(path.hasPrefix("attachments/20261002-140509-"))
    }

    @Test func tiffConvertedToPNG() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try AttachmentStore(vaultRoot: root).save(imageData: sampleTIFF(), uti: .tiff)
        #expect(path.hasSuffix(".png"))
        let bytes = try Data(contentsOf: root.appendingPathComponent(path))
        #expect(bytes.prefix(4) == pngMagic)
    }

    @Test func jpegKeepsItsFormat() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let rep = NSBitmapImageRep(data: samplePNG())!
        let jpeg = rep.representation(using: .jpeg, properties: [:])!
        let path = try AttachmentStore(vaultRoot: root).save(imageData: jpeg, uti: .jpeg)
        #expect(path.hasSuffix(".jpg") || path.hasSuffix(".jpeg"))
        #expect(try Data(contentsOf: root.appendingPathComponent(path)) == jpeg)
    }

    @Test func importKeepsExtensionAndBytes() throws {
        let root = try makeTempVault()
        let outside = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let source = outside.appendingPathComponent("照片.HEIC")
        let bytes = Data([1, 2, 3, 4, 5])
        try bytes.write(to: source)
        let path = try AttachmentStore(vaultRoot: root).importFile(source)
        #expect(path.hasSuffix(".heic"))
        #expect(try Data(contentsOf: root.appendingPathComponent(path)) == bytes)
    }

    @Test func twoSavesNeverCollide() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AttachmentStore(vaultRoot: root)
        let date = Date()
        let paths = try (0..<20).map { _ in try store.save(imageData: samplePNG(), uti: .png, date: date) }
        #expect(Set(paths).count == 20)
    }

    @Test func attachmentsFolderIsHiddenFromNeitherScannerNorWatcher() throws {
        // Only notes are listed, so images in attachments/ do not clutter the folder tree.
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try AttachmentStore(vaultRoot: root).save(imageData: samplePNG(), uti: .png)
        let tree = try VaultScanner.scan(root: root)
        #expect(tree.allNotes().isEmpty)
    }
}
