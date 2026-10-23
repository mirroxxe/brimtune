import Foundation
import os

/// Brimtune's diagnostics, readable with:
///   log show --last 15m --predicate 'subsystem == "app.brimtune.mac"'
/// NSLog text shows up as <private> in the system log, which makes it useless for
/// diagnosing a Mac you can't sit at; these messages are public. Song titles stay out.
func brimtuneLog(_ format: String, _ args: CVarArg...) {
    let message = String(format: format, arguments: args)
    BrimtuneLogger.shared.notice("\(message, privacy: .public)")
}

private enum BrimtuneLogger {
    static let shared = Logger(subsystem: "app.brimtune.mac", category: "general")
}
