//
//  RuntimeWarnings.swift
//  Dependence
//

import Foundation
#if canImport(os)
import os
#endif

/// Internal API for surfacing purple Xcode runtime warnings without crashing.
///
/// This is the production fallback when no test framework is loaded. On Apple
/// platforms Xcode renders an `os_log` of type `.fault` as a purple warning in
/// the Issue navigator and the debugger output. On platforms where `os` is
/// unavailable (Linux, Windows) the message is written to `stderr` instead.
@usableFromInline
package enum RuntimeWarning {
    /// Privacy classification applied to the *message* portion of the log
    /// line. Defaults to `.private` so application-supplied strings never
    /// leak into system logs unredacted. Apps that have audited their issue
    /// messages and are confident no PII flows through them can flip this to
    /// `.public` at startup.
    ///
    /// The file/line decoration is always logged as `.public` — file paths
    /// and line numbers are part of the source code, not user data.
    @usableFromInline
    nonisolated(unsafe) package static var messagePrivacy: MessagePrivacy = .private

    /// Privacy choices exposed to apps without leaking the `os` types
    /// (which aren't available on Linux).
    @usableFromInline
    package enum MessagePrivacy: Sendable {
        case `public`
        case `private`
    }

    /// Emit a runtime warning. On Apple platforms it surfaces in the Xcode
    /// debugger console and Issue navigator; elsewhere it goes to `stderr`.
    @inlinable
    package static func emit(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        #if canImport(os)
        let logger = Logger(subsystem: "com.dependence", category: "RuntimeWarning")
        let fileText = String(describing: file)
        switch messagePrivacy {
        case .public:
            #if DEBUG
            logger.fault("\(message, privacy: .public) (\(fileText, privacy: .public):\(line))")
            #else
            logger.warning("\(message, privacy: .public) (\(fileText, privacy: .public):\(line))")
            #endif
        case .private:
            #if DEBUG
            logger.fault("\(message, privacy: .private) (\(fileText, privacy: .public):\(line))")
            #else
            logger.warning("\(message, privacy: .private) (\(fileText, privacy: .public):\(line))")
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
