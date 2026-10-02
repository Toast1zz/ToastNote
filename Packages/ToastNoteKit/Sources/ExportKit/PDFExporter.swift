import AppKit
import Foundation
import WebKit

public enum PDFExportError: Error, Equatable {
    case loadFailed
    case printFailed
}

/// Prints HTML to a paginated A4 PDF with an off-screen `WKWebView`, which exists only for the duration of the
/// export (spec §3, §10.6): the app has no web view in its normal life.
@MainActor
public final class PDFExporter {
    public init() {}

    /// - Parameters:
    ///   - baseURL: a folder to put the temporary HTML file in; it is deleted afterwards.
    ///   - readAccess: the folder the page may read images from (the vault). It must contain `baseURL`.
    public func export(html: String, baseURL: URL, readAccess: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let page = baseURL.appendingPathComponent("export-\(UUID().uuidString).html")
        try html.write(to: page, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: page) }

        // A4 in points, with 20 mm margins.
        let paper = NSSize(width: 595.28, height: 841.89)
        let margin: CGFloat = 56.69
        let webView = WKWebView(frame: NSRect(origin: .zero, size: NSSize(width: paper.width - 2 * margin, height: paper.height - 2 * margin)))
        // WebKit prints only views that sit in a window; keep one far off screen for the duration.
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: paper.width, height: paper.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        defer {
            window.contentView = nil
            window.close()
        }

        let loader = PageLoader()
        webView.navigationDelegate = loader
        try await loader.load(webView, file: page, readAccess: readAccess)

        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = NSRect(origin: .zero, size: NSSize(width: paper.width - 2 * margin, height: paper.height - 2 * margin))

        let runner = PrintRunner()
        guard await runner.run(operation, in: window) else { throw PDFExportError.printFailed }
    }
}

@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ webView: WKWebView, file: URL, readAccess: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadFileURL(file, allowingReadAccessTo: readAccess)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: PDFExportError.loadFailed)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: PDFExportError.loadFailed)
        continuation = nil
    }
}

@MainActor
private final class PrintRunner: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?

    func run(_ operation: NSPrintOperation, in window: NSWindow) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.continuation = continuation
            operation.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    /// AppKit calls this on the print operation's own thread, so hop to the main actor before touching state.
    @objc nonisolated func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.continuation?.resume(returning: success)
                self.continuation = nil
            }
        }
    }
}
