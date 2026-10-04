# ToastNote

A lightweight, native macOS Markdown notes app with a live preview editor and one-click AI formatting using your own API key (BYOK). AI formatting adjusts structure without changing your wording. Notes are plain `.md` files on disk, so you can use the same folder with Obsidian, iCloud Drive, or Git.

## Features

- **Live preview:** The block under the cursor shows Markdown source; other blocks display formatted content. Supports headings, lists, tasks, blockquotes, code blocks, tables, images, tags, and frontmatter.
- **One-click AI formatting** (⌘⇧L): Adjusts headings, paragraphs, lists, emphasis, and tables without changing the text. Review the result side by side before applying it, and undo with ⌘Z. If the AI changes any wording, potentially modified sentences are highlighted.
- **Folder-based note libraries:** External edits sync immediately. Pasted or dropped images are saved to `attachments/`.
- **Quick Open** (⌘P), **full-text search** (⌘⇧F, including Chinese text), and **tags** with nested hierarchies such as `#parent/child`.
- **Tabs, pinned notes, and focus mode**, plus **PDF export** with A4 pagination (⌘⇧E).
- Light and dark modes, the system accent color, and support for Increase Contrast and Reduce Motion.

## Set up AI (DeepSeek example)

1. Create an API key on the [DeepSeek Platform](https://platform.deepseek.com/).
2. Open ToastNote → Settings (⌘,) → AI, select **DeepSeek**, and enter your key in the API Key field. The key is stored only in the macOS Keychain.
3. Test the connection and confirm that it succeeds.
4. Open a note, then click the wand button in the toolbar or press ⌘⇧L.

You can also choose Anthropic, OpenAI, OpenRouter, or local Ollama, or use the + button to add any OpenAI-compatible service. Additional instructions are appended to the prompt—for example, “Use - for all list items.”

## Build

Requires macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
# Run tests
swift test --package-path Packages/ToastNoteKit

# Generate the project and build
xcodegen generate
xcodebuild -project ToastNote.xcodeproj -scheme ToastNote -configuration Debug -destination 'platform=macOS' build

# Package a DMG (see docs/RELEASING.md)
bash scripts/build-dmg.sh
```

Generate a test library with 1,000 notes: `bash scripts/make-test-vault.sh /tmp/tn-vault 1000`. The app icon master is `docs/AppIcon-master.png` (1024×1024); the sizes in `AppIcon.appiconset` are scaled from it.

Design specifications are in `docs/superpowers/specs/`, implementation plans in `docs/superpowers/plans/`, and performance notes in `docs/perf-log.md`.

## Unsigned builds

Current builds are not signed with an Apple Developer account or notarized by Apple. On first launch, right-click ToastNote.app in Finder and choose Open.

## License

MIT
