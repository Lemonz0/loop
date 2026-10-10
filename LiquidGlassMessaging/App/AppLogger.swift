import Foundation
import OSLog

public enum LogLevel: String, Sendable, CaseIterable, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

public enum LogCategory: String, Sendable, CaseIterable, Codable {
    case network = "NETWORK"
    case media = "MEDIA"
    case calling = "CALLING"
    case theme = "THEME"
    case ui = "UI"
    case general = "GENERAL"
}

public struct LogEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let metadata: [String: String]?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Unified on-device diagnostic logger maintaining an in-memory ring buffer for the real-time Settings In-App Console.
@Observable
@MainActor
public final class AppLogger {
    public static let shared = AppLogger()
    
    public private(set) var entries: [LogEntry] = []
    private let maxEntries = 1000
    
    private let osLoggers: [LogCategory: os.Logger]
    
    private init() {
        let subsystem = "com.lemonz.liquidglass"
        var loggers: [LogCategory: os.Logger] = [:]
        for cat in LogCategory.allCases {
            loggers[cat] = os.Logger(subsystem: subsystem, category: cat.rawValue)
        }
        self.osLoggers = loggers
        
        self.info(.general, "Loop Client Diagnostic Logger initialized.")
    }
    
    // MARK: - Logging APIs
    
    public func log(_ level: LogLevel, _ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        let entry = LogEntry(level: level, category: category, message: message, metadata: metadata)
        
        // 1. In-memory ring buffer (keep last 1000)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        // 2. Apple Unified Logging System (os.Logger)
        let osLog = osLoggers[category] ?? os.Logger(subsystem: "com.lemonz.liquidglass", category: "General")
        let metaString = metadata != nil ? " \(metadata!)" : ""
        switch level {
        case .debug:
            osLog.debug("\(message, privacy: .public)\(metaString, privacy: .public)")
        case .info:
            osLog.info("\(message, privacy: .public)\(metaString, privacy: .public)")
        case .warn:
            osLog.warning("\(message, privacy: .public)\(metaString, privacy: .public)")
        case .error:
            osLog.error("\(message, privacy: .public)\(metaString, privacy: .public)")
        }
    }
    
    public func debug(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.debug, category, message, metadata: metadata)
    }
    
    public func info(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.info, category, message, metadata: metadata)
    }
    
    public func warn(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.warn, category, message, metadata: metadata)
    }
    
    public func error(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.error, category, message, metadata: metadata)
    }
    
    public func clear() {
        entries.removeAll()
        info(.general, "Diagnostic in-memory log buffer cleared.")
    }
    
    // MARK: - Export Utilities
    
    public func exportPlainText() -> String {
        let formatter = ISO8601DateFormatter()
        var output = "=== Loop Diagnostic Export ===\n"
        output += "Timestamp: \(formatter.string(from: Date()))\n"
        output += "Total Entries: \(entries.count)\n\n"
        
        for entry in entries {
            let metaStr = entry.metadata != nil ? " | \(entry.metadata!)" : ""
            output += "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)\(metaStr)\n"
        }
        return output
    }
    
    public func exportFileURL() -> URL? {
        let text = exportPlainText()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("liquidglass-diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
