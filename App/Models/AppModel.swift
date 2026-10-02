import AppKit
import EditorKit
import ExportKit
import UniformTypeIdentifiers
import IndexKit
import Observation
import SwiftUI
import VaultKit

@MainActor @Observable
final class AppModel {
    private(set) var vaultRoot: URL?
    private(set) var tree = FolderNode(path: "", name: "")
    private(set) var workspace = WorkspaceState()
    private(set) var currentSession: NoteSession?
    private(set) var recentVaults: [URL] = []
    var expandedFolders: Set<String> = []
    /// Sidebar sections the user collapsed ("置顶", "已打开", "文件夹", "标签"); the tag section starts collapsed.
    private(set) var collapsedSections: Set<String> = ["标签"]
    /// Path of the selected sidebar row (a note or a folder); drives where ⌘N creates notes.
    var selection: String?
    var columnVisibility: NavigationSplitViewVisibility = .all
    var errorMessage: String?
    var isQuickOpenPresented = false

    // MARK: Index, tags and search state
    private(set) var tagCounts: [TagCount] = []
    var expandedTags: Set<String> = []
    /// The tag whose notes the sidebar is listing, if any.
    private(set) var selectedTag: String?
    private(set) var tagNotes: [NoteRef] = []
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    private(set) var searchResults: [SearchHit] = []
    /// Bumped by ⌘⇧F; the search field focuses itself when it changes.
    private(set) var searchFocusToken = 0
    /// Most recently opened notes, newest first (at most 10); quick open lists them for an empty query.
    private(set) var recentPaths: [String] = []

    /// The editor of the open note, for commands, AI formatting and search highlights.
    @ObservationIgnored weak var activeTextView: MarkdownTextView?

    @ObservationIgnored private let registry = SelfWriteRegistry()
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var ops: VaultFileOps?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// One session per tab, created lazily; at most `maxLiveSessions` are kept, least recently used first out.
    @ObservationIgnored private var sessions: [String: NoteSession] = [:]
    @ObservationIgnored private var sessionUse: [String] = []
    /// The deleted note shown with its "已被删除" banner; its tab goes away when the user leaves it.
    @ObservationIgnored private var deletedCurrent: String?
    @ObservationIgnored private var index: NoteIndex?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var pendingHighlight: (path: String, terms: [String])?
    @ObservationIgnored private let persistDebouncer = Debouncer(delay: .milliseconds(500))

    private static let recentKey = "recentVaults"
    private static let maxLiveSessions = 10

    init() {
        recentVaults = (defaults.stringArray(forKey: Self.recentKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushAll() }
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
        flushAll()
        sessions.removeAll()
        sessionUse.removeAll()
        deletedCurrent = nil
        currentSession = nil
        selection = nil
        watcher?.stop()
        vaultRoot = url
        ops = VaultFileOps(root: url)
        rememberRecent(url)
        restoreWorkspace(for: url)
        refreshTree()
        startIndex(for: url)
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
        updateIndex(with: changes)
        for change in changes {
            for session in sessions.values { session.handle(change) }
            switch change {
            case .removed(let path) where isCurrent(path):
                // Keep the tab so its "此笔记已被删除" banner can be answered.
                deletedCurrent = path
                var others = workspace
                others.apply(change)
                workspace.pinned = others.pinned
                workspace.open = workspace.open.filter { others.open.contains($0) || $0 == workspace.current }
            case .renamed(let from, let to):
                rekeySessions(from: from, to: to)
                workspace.apply(change)
            default:
                workspace.apply(change)
            }
        }
        sessionsDidChange()
    }

    // MARK: Index and search

    private func startIndex(for root: URL) {
        index = nil
        tagCounts = []
        selectedTag = nil
        searchText = ""
        let database = VaultIdentity.supportDirectory(for: root).appendingPathComponent("index.sqlite")
        guard let index = try? NoteIndex(databaseURL: database, vaultRoot: root) else { return }
        self.index = index
        // Indexing is low priority and never blocks the window (spec §3).
        Task(priority: .utility) { [weak self] in
            try? await index.sync()
            await self?.refreshIndexViews()
        }
    }

    private func updateIndex(with changes: [VaultChange]) {
        guard let index else { return }
        Task(priority: .utility) { [weak self] in
            try? await index.apply(changes)
            await self?.refreshIndexViews()
        }
    }

    /// Reloads everything the sidebar shows from the index: tags, the open tag list and search results.
    private func refreshIndexViews() async {
        guard let index else { return }
        tagCounts = (try? await index.tags()) ?? []
        if let tag = selectedTag { await loadTagNotes(tag) }
        if !searchText.isEmpty { searchResults = (try? await index.search(searchText)) ?? [] }
    }

    func focusSearch() {
        columnVisibility = .all
        searchFocusToken += 1
    }

    func clearSearch() {
        searchText = ""
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty, let index else {
            searchResults = []
            return
        }
        // 120 ms debounce while typing (spec §10.4).
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let hits = (try? await index.search(query)) ?? []
            guard !Task.isCancelled else { return }
            self?.searchResults = hits
        }
    }

    func selectTag(_ tag: String?) {
        selectedTag = tag
        tagNotes = []
        guard let tag else { return }
        Task { await loadTagNotes(tag) }
    }

    private func loadTagNotes(_ tag: String) async {
        guard let index else { return }
        let paths = (try? await index.notes(taggedWith: tag)) ?? []
        tagNotes = paths.map { NoteRef(path: $0, title: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension) }
    }

    /// Opens a search hit, then marks every match in the editor and scrolls to the first (spec §10.4).
    func openSearchResult(_ hit: SearchHit) {
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.hasPrefix("#") }
        pendingHighlight = (hit.path, terms)
        open(path: hit.path)
        applyPendingHighlight(to: activeTextView)
    }

    /// Called whenever an editor view appears; highlights only if it shows the note the search opened.
    func applyPendingHighlight(to textView: MarkdownTextView?) {
        guard let pending = pendingHighlight, let textView, let session = currentSession,
              session.path == pending.path, textView.string == session.text else { return }
        pendingHighlight = nil
        textView.highlightMatches(of: pending.terms)
    }

    private func isCurrent(_ path: String) -> Bool {
        guard let current = workspace.current else { return false }
        return current == path || current.hasPrefix(path + "/")
    }

    // MARK: Tabs

    /// Focuses the note's tab, adding one after the current tab when needed.
    func open(path: String) {
        guard vaultRoot != nil, workspace.current != path else { return }
        leaveCurrent()
        workspace.open(path)
        noteRecent(path)
        sessionsDidChange()
    }

    private func noteRecent(_ path: String) {
        recentPaths.removeAll { $0 == path }
        recentPaths.insert(path, at: 0)
        recentPaths = Array(recentPaths.prefix(10))
    }

    /// Notes for quick open's empty query, skipping files that no longer exist.
    func recentNotes() -> [NoteRef] {
        let known = Dictionary(uniqueKeysWithValues: tree.allNotes().map { ($0.path, $0) })
        return recentPaths.compactMap { known[$0] }
    }

    /// "新建笔记“xxx”" in quick open: a note named after the query, in the selected folder.
    func createNote(titled title: String) {
        let name = title.replacingOccurrences(of: "/", with: "-")
        perform {
            let folder = targetFolder
            guard let note = try ops?.createNote(inFolder: folder) else { return }
            let path = (try? ops?.rename(path: note.path, to: name)) ?? note.path
            refreshTree()
            if !folder.isEmpty { expandedFolders.insert(folder) }
            open(path: path)
        }
    }

    func selectNext() { change { $0.selectNext() } }
    func selectPrevious() { change { $0.selectPrevious() } }
    func select(index: Int) { change { $0.select(index: index) } }

    func close(path: String) {
        if workspace.current == path { leaveCurrent() }
        workspace.close(path)
        if !workspace.ordered.contains(path) { dropSession(path) }
        sessionsDidChange()
    }

    func closeCurrent() {
        if let current = workspace.current { close(path: current) }
    }

    func pin(path: String) {
        workspace.pin(path)
        sessionsDidChange()
    }

    func unpin(path: String) {
        workspace.unpin(path)
        sessionsDidChange()
    }

    func moveOpen(from offsets: IndexSet, to destination: Int) {
        workspace.moveOpen(from: offsets, to: destination)
        sessionsDidChange()
    }

    private func change(_ mutate: (inout WorkspaceState) -> Void) {
        let before = workspace.current
        mutate(&workspace)
        if workspace.current != before {
            if let before, let session = sessions[before] { session.saveNow() }
            if let before, deletedCurrent == before { forgetDeleted(before) }
        }
        sessionsDidChange()
    }

    /// Saves the tab being left; a deleted note that is left behind loses its tab.
    private func leaveCurrent() {
        guard let current = workspace.current else { return }
        sessions[current]?.saveNow()
        if deletedCurrent == current { forgetDeleted(current) }
    }

    private func forgetDeleted(_ path: String) {
        deletedCurrent = nil
        workspace.apply(.removed(path))
        dropSession(path)
    }

    // MARK: Sessions

    /// Creates the current tab's session when needed and publishes the derived state.
    private func sessionsDidChange() {
        if let current = workspace.current {
            currentSession = session(for: current)
            if selection == nil || selection.map(isNotePath) == true { selection = current }
        } else {
            currentSession = nil
        }
        trimSessions()
        scheduleSave()
    }

    private func session(for path: String) -> NoteSession? {
        guard let root = vaultRoot else { return nil }
        sessionUse.removeAll { $0 == path }
        sessionUse.append(path)
        if let existing = sessions[path] { return existing }
        let session = NoteSession(root: root, path: path, registry: registry)
        session.onClose = { [weak self, weak session] in
            guard let self, let session else { return }
            self.removeTab(session.path)
        }
        session.load()
        sessions[path] = session
        return session
    }

    /// A tab whose file is gone for good: drop it from pinned and open alike.
    private func removeTab(_ path: String) {
        if deletedCurrent == path { deletedCurrent = nil }
        workspace.apply(.removed(path))
        dropSession(path)
        sessionsDidChange()
    }

    private func dropSession(_ path: String) {
        sessions[path]?.saveNow()
        sessions[path] = nil
        sessionUse.removeAll { $0 == path }
    }

    private func rekeySessions(from: String, to: String) {
        for key in Array(sessions.keys) where key == from || key.hasPrefix(from + "/") {
            let newKey = to + key.dropFirst(from.count)
            sessions[newKey] = sessions.removeValue(forKey: key)
            sessions[newKey]?.handle(.renamed(from: key, to: newKey))
            sessionUse = sessionUse.map { $0 == key ? newKey : $0 }
        }
        if deletedCurrent == from { deletedCurrent = to }
    }

    private func trimSessions() {
        while sessions.count > Self.maxLiveSessions {
            guard let victim = sessionUse.first(where: { $0 != workspace.current && sessions[$0]?.isDirty != true }) else { break }
            dropSession(victim)
        }
    }

    private func flushAll() {
        for session in sessions.values { session.saveNow() }
        persistDebouncer.flush()
    }

    private func isNotePath(_ path: String) -> Bool {
        path.hasSuffix(".md") || path.hasSuffix(".markdown")
    }

    // MARK: Persistence (pinned in the vault, tabs per device)

    private func restoreWorkspace(for root: URL) {
        let pinned = WorkspaceFiles.loadPinned(vault: root).pinned
        let session = WorkspaceFiles.loadSession(vault: root)
        recentPaths = session.recent
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        let pinnedAlive = pinned.filter(exists)
        let openAlive = session.open.filter { exists($0) && !pinnedAlive.contains($0) }
        let current = session.current.flatMap { ($0.isEmpty || !exists($0)) ? nil : $0 }
        workspace = WorkspaceState(pinned: pinnedAlive, open: openAlive, current: current ?? openAlive.first ?? pinnedAlive.first)
        collapsedSections = session.collapsedSections.isEmpty && session.open.isEmpty && session.current == nil
            ? ["标签"] : session.collapsedSections
        sessionsDidChange()
    }

    private func scheduleSave() {
        guard let root = vaultRoot else { return }
        let state = workspace
        let collapsed = collapsedSections
        let recent = recentPaths
        persistDebouncer.schedule {
            try? WorkspaceFiles.save(PinnedFile(pinned: state.pinned), vault: root)
            try? WorkspaceFiles.save(
                SessionFile(open: state.open, current: state.current, collapsedSections: collapsed, recent: recent),
                vault: root
            )
        }
    }

    func toggleSection(_ name: String) {
        if collapsedSections.contains(name) { collapsedSections.remove(name) } else { collapsedSections.insert(name) }
        scheduleSave()
    }

    // MARK: Notes and folders

    /// Folder that new notes and folders go into: the selected folder, or the selected note's folder.
    var targetFolder: String {
        guard let selection else { return "" }
        if isNotePath(selection) { return (selection as NSString).deletingLastPathComponent }
        return selection
    }

    func newNote(inFolder folder: String? = nil) {
        perform {
            let target = folder ?? targetFolder
            guard let note = try ops?.createNote(inFolder: target) else { return }
            refreshTree()
            if !target.isEmpty { expandedFolders.insert(target) }
            open(path: note.path)
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
        let isNote = isNotePath(path)
        let leaf = (path as NSString).lastPathComponent
        let initial = isNote ? (leaf as NSString).deletingPathExtension : leaf
        guard let name = promptForText(title: "重命名", message: "新名称", defaultValue: initial), name != initial else { return }
        perform {
            guard let newPath = try ops?.rename(path: path, to: name) else { return }
            rekeySessions(from: path, to: newPath)
            workspace.apply(.renamed(from: path, to: newPath))
            recentPaths = recentPaths.map { $0 == path ? newPath : $0 }
            if selection == path { selection = newPath }
            sessionsDidChange()
            refreshTree()
        }
    }

    func trash(path: String) {
        guard let ops else { return }
        Task {
            do {
                try await ops.trash(path: path)
                workspace.apply(.removed(path))
                for key in Array(sessions.keys) where key == path || key.hasPrefix(path + "/") { sessions[key] = nil }
                sessionUse.removeAll { $0 == path || $0.hasPrefix(path + "/") }
                if selection == path { selection = nil }
                sessionsDidChange()
                refreshTree()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: PDF export (spec §10.6)

    private(set) var isExporting = false
    /// Set by tests and automation to skip the save panel.
    @ObservationIgnored var exportDestinationOverride: URL?

    /// ⌘⇧E: saves the open note as an A4 PDF in light colors, paginated.
    func exportPDF() {
        guard let session = currentSession, let root = vaultRoot, !isExporting else { return }
        session.saveNow()
        let title = ((session.path as NSString).lastPathComponent as NSString).deletingPathExtension
        let destination: URL
        #if DEBUG
        // Automation hook for debug builds: skips the save panel.
        let environmentTarget = ProcessInfo.processInfo.environment["TOASTNOTE_EXPORT_TO"].map { URL(fileURLWithPath: $0) }
        #else
        let environmentTarget: URL? = nil
        #endif
        if let override = exportDestinationOverride ?? environmentTarget {
            destination = override
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = title + ".pdf"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        }
        let html = HTMLRenderer.render(markdown: session.text, notePath: session.path, vaultRoot: root, title: title)
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                // The page file lives in the vault's hidden folder so the page may read the vault's images.
                try await PDFExporter().export(
                    html: html, baseURL: root.appendingPathComponent(".toastnote"), readAccess: root, to: destination
                )
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                errorMessage = "导出 PDF 失败：\(error.localizedDescription)"
            }
        }
    }

    func revealInFinder(path: String) {
        guard let root = vaultRoot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(path)])
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
