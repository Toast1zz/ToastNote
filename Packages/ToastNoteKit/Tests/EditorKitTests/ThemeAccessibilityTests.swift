import AppKit
import Foundation
import Testing
@testable import EditorKit

@Suite struct ThemeAccessibilityTests {
    private func color(_ theme: EditorTheme, _ role: TextStyle.Role) -> NSColor? {
        theme.attributes(for: TextStyle(role: role))[.foregroundColor] as? NSColor
    }

    @Test func secondaryTextIsSecondaryByDefault() {
        let theme = EditorTheme.default
        #expect(color(theme, .marker) == NSColor.secondaryLabelColor)
        #expect(color(theme, .quote) == NSColor.secondaryLabelColor)
        #expect(color(theme, .taskDone) == NSColor.secondaryLabelColor)
        #expect(color(theme, .frontmatterSummary) == NSColor.secondaryLabelColor)
    }

    @Test func increasedContrastSwapsSecondaryTextForLabelColor() {
        // Spec §9.7: with "Increase contrast" on, secondary text becomes labelColor.
        let theme = EditorTheme(increasedContrast: true)
        #expect(color(theme, .marker) == NSColor.labelColor)
        #expect(color(theme, .quote) == NSColor.labelColor)
        #expect(color(theme, .taskDone) == NSColor.labelColor)
        #expect(color(theme, .frontmatterSummary) == NSColor.labelColor)
    }

    @Test func bodyAndAccentColorsAreUnchangedByContrast() {
        let theme = EditorTheme(increasedContrast: true)
        #expect(color(theme, .body) == NSColor.labelColor)
        #expect(color(theme, .link) == NSColor.controlAccentColor)
        #expect(color(theme, .tag) == NSColor.controlAccentColor)
    }

    @Test func settingsRangesAreClamped() {
        #expect(EditorTheme(bodySize: 8).bodySize == 13)
        #expect(EditorTheme(bodySize: 40).bodySize == 20)
        #expect(EditorTheme(maxContentWidth: 100).maxContentWidth == 600)
        #expect(EditorTheme(maxContentWidth: 5000).maxContentWidth == 1200)
    }

    @Test func themesWithDifferentContrastAreNotEqual() {
        #expect(EditorTheme(increasedContrast: true) != EditorTheme())
    }
}
