import Foundation
import Observation

public enum SessionBanner: Equatable, Sendable {
    case modifiedExternally
    case deletedExternally
}

public enum BannerChoice: Sendable {
    case loadTheirs, keepMine, resave, close
}

/// One open note: its text, autosave, and how it reacts to changes made outside the app (spec §6.2–6.3).
@MainActor @Observable
public final class NoteSession {
    public private(set) var path: String
    public private(set) var text: String = ""
    public private(set) var isDirty = false
    public private(set) var banner: SessionBanner?
    public private(set) var loadError: NoteFileError?
    /// Set by the app; invoked when the user chooses to close a deleted note.
    @ObservationIgnored public var onClose: (() -> Void)?

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let registry: SelfWriteRegistry
    @ObservationIgnored private let debouncer: Debouncer
    /// What we believe is on disk; edits are compared against it to decide whether a save is needed.
    @ObservationIgnored private var diskText = ""
    /// Set by "keep mine" / "re-save" so the next save writes even when the text equals `diskText`.
    @ObservationIgnored private var forceWrite = false

    public init(root: URL, path: String, registry: SelfWriteRegistry, autosaveDelay: Duration = .seconds(1)) {
        self.root = root
        self.path = path
        self.registry = registry
        self.debouncer = Debouncer(delay: autosaveDelay)
    }

    private var fileURL: URL { root.appendingPathComponent(path) }

    public func load() {
        debouncer.cancel()
        reloadFromDisk()
    }

    public func userEdited(_ newText: String) {
        // A file that failed to load is read-only: never let edits reach it.
        guard loadError == nil, newText != text else { return }
        text = newText
        isDirty = newText != diskText
        debouncer.schedule { [weak self] in self?.saveNow() }
    }

    public func saveNow() {
        debouncer.cancel()
        guard loadError == nil, banner == nil, isDirty || forceWrite else { return }
        do {
            try NoteFile.write(text, to: fileURL)
        } catch {
            return
        }
        if let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date {
            registry.record(path: path, modificationDate: mtime)
        }
        diskText = text
        isDirty = false
        forceWrite = false
    }

    public func handle(_ change: VaultChange) {
        switch change {
        case .modified(let changed), .created(let changed):
            if changed == path { externalChange() }
        case .removed(let removed):
            if removed == path { banner = .deletedExternally }
        case .renamed(let from, let to):
            if from == path {
                path = to
            } else if to == path {
                externalChange()
            }
        }
    }

    public func resolveBanner(_ choice: BannerChoice) {
        switch choice {
        case .loadTheirs:
            reloadFromDisk()
        case .keepMine:
            banner = nil
            forceWrite = true
            debouncer.schedule { [weak self] in self?.saveNow() }
        case .resave:
            banner = nil
            forceWrite = true
            saveNow()
        case .close:
            onClose?()
        }
    }

    private func externalChange() {
        if isDirty {
            banner = .modifiedExternally
        } else if let onDisk = try? NoteFile.read(fileURL) {
            // Skip identical content so a spurious event does not disturb the caret.
            if onDisk != text || banner != nil { reloadFromDisk() }
        } else {
            reloadFromDisk()
        }
    }

    private func reloadFromDisk() {
        banner = nil
        forceWrite = false
        do {
            let onDisk = try NoteFile.read(fileURL)
            text = onDisk
            diskText = onDisk
            isDirty = false
            loadError = nil
        } catch let error as NoteFileError {
            loadError = error
            text = ""
            diskText = ""
            isDirty = false
        } catch {
            loadError = .missing
        }
    }
}
