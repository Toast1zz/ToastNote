import SwiftUI
import VaultKit

/// Banner for the open note: external changes, deletion, and files that cannot be edited.
struct SessionBannerView: View {
    let session: NoteSession

    var body: some View {
        if let message {
            EditorBanner(message: message, actions: actions.map { title, choice in
                EditorBanner.Action(title: title) { session.resolveBanner(choice) }
            })
        }
    }

    private var message: String? {
        if let error = session.loadError {
            return error == .notUTF8 ? "无法以 UTF-8 打开此文件，已设为只读" : "无法读取此文件，已设为只读"
        }
        switch session.banner {
        case .modifiedExternally: return "此笔记已在其他地方被修改"
        case .deletedExternally: return "此笔记已被删除"
        case nil: return nil
        }
    }

    private var actions: [(String, BannerChoice)] {
        guard session.loadError == nil else { return [] }
        switch session.banner {
        case .modifiedExternally: return [("载入新版本", .loadTheirs), ("保留我的版本", .keepMine)]
        case .deletedExternally: return [("重新保存", .resave), ("关闭", .close)]
        case nil: return []
        }
    }
}
