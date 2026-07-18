//
//  RuntimeWarnings.swift
//  Dependence
//

import Foundation
import Synchronization

#if canImport(os)
    import os
#endif

/// Internal API for surfacing purple Xcode runtime warnings without crashing.
///
/// This is the production fallback when no test framework is loaded. On Apple
/// platforms the message is logged to the `com.apple.runtime-issues`
/// subsystem — the one Xcode's runtime-issue machinery matches — so it
/// surfaces as a purple runtime issue in the Issue navigator and the debugger
/// console. On platforms where `os` is unavailable (Linux, Windows) the
/// message is written to `stderr` instead.
@usableFromInline
package enum RuntimeWarning {
    /// Privacy choices exposed to apps without leaking the `os` types
    /// (which aren't available on Linux).
    package enum MessagePrivacy: Sendable {
        case `public`
        case `private`
    }

    /// Privacy classification applied to the *message* portion of the log
    /// line.
    ///
    /// Defaults to `.public`: issue messages are made of dependency key
    /// names, type names, and diagnostic prose — source-level identifiers,
    /// not user data — and a redacted `<private>` runtime issue is useless
    /// for debugging. Apps that interpolate sensitive values into custom
    /// `reportIssue` messages can flip this to `.private` at startup.
    ///
    /// The file/line decoration is always logged as `.public` — file paths
    /// and line numbers are part of the source code, not user data.
    package static var messagePrivacy: MessagePrivacy {
        get { _messagePrivacy.withLock { $0 } }
        set { _messagePrivacy.withLock { $0 = newValue } }
    }

    /// Mutex-backed storage for ``messagePrivacy``.
    ///
    /// The knob is written once at startup and read on the (cold) emit path,
    /// but a bare `nonisolated(unsafe) static var` would still be a data
    /// race the moment any code writes it after launch.
    private static let _messagePrivacy = Mutex<MessagePrivacy>(.public)

    #if canImport(os)
        /// Cached logger — `Logger` construction is not free, and `emit`
        /// used to rebuild it on every call.
        ///
        /// The `com.apple.runtime-issues` subsystem is load-bearing: it is
        /// the marker Xcode uses to render a log record as a purple runtime
        /// issue.
        private static let logger = Logger(
            subsystem: "com.apple.runtime-issues",
            category: "Dependence"
        )
    #endif

    /// Emit a runtime warning.
    ///
    /// On Apple platforms it surfaces as a runtime issue in the Xcode Issue
    /// navigator and the debugger console; elsewhere it goes to `stderr`.
    /// DEBUG builds log at `.fault` so the issue is maximally visible during
    /// development; release builds log at the default level.
    @usableFromInline
    package static func emit(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        #if canImport(os)
            let fileText = String(describing: file)
            switch messagePrivacy {
                case .public:
                    #if DEBUG
                        logger.fault("\(message, privacy: .public) (\(fileText, privacy: .public):\(line))")
                    #else
                        logger.log("\(message, privacy: .public) (\(fileText, privacy: .public):\(line))")
                    #endif
                case .private:
                    #if DEBUG
                        logger.fault("\(message, privacy: .private) (\(fileText, privacy: .public):\(line))")
                    #else
                        logger.log("\(message, privacy: .private) (\(fileText, privacy: .public):\(line))")
                    #endif
            }
        #else
            // Non-Apple platforms: write to stderr. The privacy knob is irrelevant
            // here (no system log redaction layer), so we always emit the full
            // message — same observability the developer would get from `print`.
            let line = "[Dependence] \(message) (\(file):\(line))\n"
            FileHandle.standardError.write(Data(line.utf8))
        #endif
    }
}
