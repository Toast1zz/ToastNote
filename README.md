# ToastNote

原生、轻量的 macOS Markdown 笔记应用：实时渲染的编辑器，加上自带 API Key（BYOK）的 AI 一键排版（只改结构，不改措辞）。笔记就是磁盘上的普通 `.md` 文件，可以和 Obsidian、iCloud Drive、Git 共用同一个文件夹。

设计规格见 `docs/superpowers/specs/`，实现计划见 `docs/superpowers/plans/`。

## 构建

需要 macOS 14+、Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
# 运行测试
swift test --package-path Packages/ToastNoteKit

# 生成工程并构建
xcodegen generate
xcodebuild -project ToastNote.xcodeproj -scheme ToastNote -configuration Debug -destination 'platform=macOS' build
```

生成 1000 篇笔记的测试库：`bash scripts/make-test-vault.sh /tmp/tn-vault 1000`。

## 未签名构建

目前的构建没有 Apple 开发者账号签名与公证。首次打开时请在 Finder 中右键点击 ToastNote.app，选择“打开”。

## 许可证

MIT
