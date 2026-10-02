import os

/// Signposts for Instruments; `restyle` covers parse + style + apply for one edit (spec §7.4).
enum EditorSignposts {
    static let signposter = OSSignposter(subsystem: "app.toastnote", category: "editor")
}
