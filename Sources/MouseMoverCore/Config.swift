import Foundation
import os

enum Log {
    static let core = Logger(subsystem: "io.github.alexandrebeauduin.MouseMover", category: "core")
}

/// How the pattern played on each cycle is chosen.
public enum PatternMode: String, Codable, CaseIterable, Sendable {
    /// Always the same pattern.
    case single
    /// A random pattern among the checked ones.
    case random
    /// The checked patterns, one after the other.
    case sequence
}

public struct MouseMoverConfig: Codable, Equatable {
    public static let defaultIntervalSeconds = 300
    public static let defaultPatternIDs = [MousePattern.classic.id]

    public var intervalSeconds: Int
    public var launchAtLogin: Bool
    public var displayID: UInt32?
    /// Patterns created by the user (built-in patterns are never saved).
    public var patterns: [MousePattern]
    public var patternMode: PatternMode
    public var selectedPatternIDs: [String]

    public init(intervalSeconds: Int = MouseMoverConfig.defaultIntervalSeconds,
                launchAtLogin: Bool = false,
                displayID: UInt32? = nil,
                patterns: [MousePattern] = [],
                patternMode: PatternMode = .single,
                selectedPatternIDs: [String] = MouseMoverConfig.defaultPatternIDs) {
        self.intervalSeconds = intervalSeconds
        self.launchAtLogin = launchAtLogin
        self.displayID = displayID
        self.patterns = patterns
        self.patternMode = patternMode
        self.selectedPatternIDs = selectedPatternIDs
    }

    enum CodingKeys: String, CodingKey {
        case intervalSeconds = "interval_seconds"
        case launchAtLogin = "launch_at_login"
        case displayID = "display_id"
        case patterns
        case patternMode = "pattern_mode"
        case selectedPatternIDs = "selected_pattern_ids"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var interval = Self.defaultIntervalSeconds
        if let value = try? container.decodeIfPresent(Int.self, forKey: .intervalSeconds) {
            interval = value
        } else if let value = try? container.decodeIfPresent(Double.self, forKey: .intervalSeconds),
                  value.isFinite, abs(value) < Double(Int.max) {
            interval = Int(value)
        }
        self.intervalSeconds = interval >= 1 ? interval : Self.defaultIntervalSeconds

        self.launchAtLogin = (try? container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? false
        self.displayID = (try? container.decodeIfPresent(UInt32.self, forKey: .displayID)) ?? nil

        let patterns = (try? container.decodeIfPresent([Lossy<MousePattern>].self, forKey: .patterns)) ?? []
        var seen = Set<String>()
        self.patterns = patterns.compactMap(\.value).filter { !$0.isBuiltIn && seen.insert($0.id).inserted }
        self.patternMode = (try? container.decodeIfPresent(PatternMode.self, forKey: .patternMode)) ?? .single
        let selected = (try? container.decodeIfPresent([String].self, forKey: .selectedPatternIDs)) ?? nil
        self.selectedPatternIDs = selected ?? Self.defaultPatternIDs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intervalSeconds, forKey: .intervalSeconds)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(patterns, forKey: .patterns)
        try container.encode(patternMode, forKey: .patternMode)
        try container.encode(selectedPatternIDs, forKey: .selectedPatternIDs)
    }
}

public struct ConfigStore {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseMover", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public func load() -> MouseMoverConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(MouseMoverConfig.self, from: data) else {
            return MouseMoverConfig()
        }
        return config
    }

    public func save(_ config: MouseMoverConfig) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
