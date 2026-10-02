import AppKit
import Foundation
import Testing
@testable import EditorKit

@MainActor private var retainedWindows: [NSWindow] = []

/// Spec §3: one keystroke must stay under 8 ms in a 10 000 character note; spec §7.4 asks for a fallback above 4 ms.
/// Debug builds are several times slower than release, so the hard limit here is generous; the printed
/// numbers are what goes into docs/perf-log.md (run with `-c release -Xswiftc -enable-testing`).
@MainActor @Suite struct RestylePerformanceTests {
    private func sampleDocument(minimumLength: Int = 10_000) -> String {
        let unit = """
        ## 小节标题

        这是一段中文正文，包含 **粗体**、*斜体*、`行内代码` 和[链接](https://example.com)，还有 #标签/子标签。
        English text with a bare URL https://example.org and ~~strike~~.

        - 列表项一
        - [ ] 待办事项
        - [x] 已完成
          - 嵌套项

        > 引用内容第一行
        > 引用内容第二行

        ```swift
        let value = 42
        print(value)
        ```


        """
        var text = ""
        while text.utf16.count < minimumLength { text += unit }
        return text
    }

    @Test func restylingATenThousandCharacterNoteIsFast() {
        let text = sampleDocument()
        let view = MarkdownTextView(theme: .default)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        retainedWindows.append(window)
        view.markdown = text

        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<20 {
            let elapsed = clock.measure { view.restyleAll() }
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("PERF restyle (\(text.utf16.count) chars): median \(String(format: "%.2f", median)) ms, max \(String(format: "%.2f", samples.last!)) ms")
        #expect(median < 60, "median restyle \(median) ms")
    }

    @Test func aKeystrokeInATenThousandCharacterNoteIsFast() {
        let text = sampleDocument()
        let view = MarkdownTextView(theme: .default)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        retainedWindows.append(window)
        view.markdown = text
        // Type in the middle of a paragraph, which is the typical edit.
        let target = (text as NSString).range(of: "中文正文", range: NSRange(location: text.utf16.count / 2, length: text.utf16.count / 2))
        view.setSelectedRange(NSRange(location: target.location + 2, length: 0))

        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<30 {
            let elapsed = clock.measure { view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)) }
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("PERF keystroke (\(text.utf16.count) chars): median \(String(format: "%.2f", median)) ms, max \(String(format: "%.2f", samples.last!)) ms")
        #expect(median < 40, "median keystroke \(median) ms")
        #expect((view.lastRestyledRange?.length ?? 0) < text.utf16.count / 4, "a keystroke must not restyle the whole note")
    }

    @Test func parseAndStyleAloneAreCheap() {
        let text = sampleDocument()
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<20 {
            let elapsed = clock.measure {
                let blocks = BlockParser.parse(text)
                _ = MarkdownStyler.style(blocks: blocks, text: text as NSString, active: IndexSet(integer: 0))
            }
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("PERF parse+style (\(text.utf16.count) chars): median \(String(format: "%.2f", median)) ms")
        #expect(median < 40, "median parse+style \(median) ms")
    }
}
