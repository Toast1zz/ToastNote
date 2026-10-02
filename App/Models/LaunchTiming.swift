import Darwin
import Foundation
import os

/// Measures cold launch to a typeable editor (spec §3): from process creation to the first time an
/// editor becomes first responder. Reported as a signpost event and a log line for Instruments / `log show`.
@MainActor
enum LaunchTiming {
    private static let signposter = OSSignposter(subsystem: "app.toastnote", category: "launch")
    private static let logger = Logger(subsystem: "app.toastnote", category: "perf")
    private static var reported = false

    static func editorReady() {
        guard !reported else { return }
        reported = true
        guard let started = processStartDate() else { return }
        let milliseconds = Date().timeIntervalSince(started) * 1000
        signposter.emitEvent("editorReady", "\(milliseconds, format: .fixed(precision: 1)) ms since process start")
        logger.info("cold launch to editor ready: \(milliseconds, format: .fixed(precision: 1)) ms")
    }

    private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
