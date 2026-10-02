import AppKit
import EditorKit
import Observation
import SwiftUI
import VaultKit

@MainActor @Observable
final class AppModel {
    private(set) var vaultRoot: URL?
    private(set) var tree = FolderNode(path: "", name: "")
    private(set) var currentSession: NoteSession?
    private(set) var recentVaults: [URL] = []
    var expandedFolders: Set<String> = []
    /// Path of the selected sidebar row (a note or a folder); drives where ⌘N creates notes.
    var selection: String?
    var columnVisibility: NavigationSplitViewVisibility = .all
    var errorMessage: String?

    /// The editor of the open note, for commands, AI formatting and search highlights.
    @ObservationIgnored weak var activeTextView: MarkdownTextView?

    @ObservationIgnored private let registry = SelfWriteRegistry()
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var ops: VaultFileOps?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let recentKey = "recentVaults"

    init() {
        recentVaults = (defaults.stringArray(forKey: Self.recentKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.currentSession?.saveNow() }
            })
        }
        reopenLastVault()
    }

    // MARK: Vault

    func reopenLastVault() {
        if let last = recentVaults.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            openVault(last)
        }
    }

    func openVault(_ url: URL) {
        currentSession?.saveNow()
        currentSession = nil
        selection = nil
        watcher?.stop()
        vaultRoot = url
        ops = VaultFileOps(root: url)
        rememberRecent(url)
        refreshTree()
        let watcher = VaultWatcher(root: url, registry: registry) { [weak self] changes in
            Task { @MainActor in self?.apply(changes) }
        }
        watcher.start()
        self.watcher = watcher
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url { openVault(url) }
    }

    func createVault() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ToastNote"
        panel.prompt = "创建"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            openVault(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rememberRecent(_ url: URL) {
        var list = recentVaults.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        recentVaults = Array(list.prefix(10))
        defaults.set(recentVaults.map(\.path), forKey: Self.recentKey)
    }

    func refreshTree() {
        guard let root = vaultRoot else { return }
        Task {
            let scanned = await Task.detached(priority: .userInitiated) { try? VaultScanner.scan(root: root) }.value
            if let scanned, vaultRoot == root { tree = scanned }
        }
    }

    private func apply(_ changes: [VaultChange]) {
        refreshTree()
        for change in changes { currentSession?.handle(change) }
    }

    // MARK: Notes

    func open(path: String) {
        guard let root = vaultRoot, currentSession?.path != path else { return }
        currentSession?.saveNow()
        let session = NoteSession(root: root, path: path, registry: registry)
        session.onClose = { [weak self, weak session] in
            guard let self, self.currentSession === session else { return }
            self.currentSession = nil
        }
        session.load()
        currentSession = session
        selection = path
    }

    /// Folder that new notes and folders go into: the selected folder, or the selected note's folder.
    var targetFolder: String {
        guard let selection else { return "" }
        if selection.hasSuffix(".md") || selection.hasSuffix(".markdown") {
            return (selection as NSString).deletingLastPathComponent
        }
        return selection
    }

    func newNote(inFolder folder: String? = nil) {
        perform {
            let note = try ops?.createNote(inFolder: folder ?? targetFolder)
            refreshTree()
            if let note {
                if !(folder ?? targetFolder).isEmpty { expandedFolders.insert(folder ?? targetFolder) }
                open(path: note.path)
            }
        }
    }

    func newFolder(inFolder folder: String? = nil) {
        guard let name = promptForText(title: "新建文件夹", message: "文件夹名称", defaultValue: "") else { return }
        perform {
            if let path = try ops?.createFolder(named: name, inFolder: folder ?? targetFolder) {
                expandedFolders.insert(path)
            }
            refreshTree()
        }
    }

    func rename(path: String) {
        let current = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let isNote = path.hasSuffix(".md") || path.hasSuffix(".markdown")
        let initial = isNote ? current : (path as NSString).lastPathComponent
        guard let name = promptForText(title: "重命名", message: "新名称", defaultValue: initial), name != initial else { return }
        perform {
            guard let newPath = try ops?.rename(path: path, to: name) else { return }
            if currentSession?.path == path { currentSession?.handle(.renamed(from: path, to: newPath)) }
            if selection == path { selection = newPath }
            refreshTree()
        }
    }

    func trash(path: String) {
        guard let ops else { return }
        Task {
            do {
                try await ops.trash(path: path)
                if let session = currentSession, session.path == path || session.path.hasPrefix(path + "/") {
                    currentSession = nil
                }
                if selection == path { selection = nil }
                refreshTree()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveNow() { currentSession?.saveNow() }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
