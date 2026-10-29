import Foundation
import os

enum Log {
    static let core = Logger(subsystem: "com.pudeldoodle.MouseMover", category: "core")
}

public struct MouseMoverConfig: Codable, Equatable {
    public static let defaultIntervalSeconds = 300

    public var intervalSeconds: Int
    public var launchAtLogin: Bool
    public var displayID: UInt32?

    public init(intervalSeconds: Int = MouseMoverConfig.defaultIntervalSeconds,
                launchAtLogin: Bool = false,
                displayID: UInt32? = nil) {
        self.intervalSeconds = intervalSeconds
        self.launchAtLogin = launchAtLogin
        self.displayID = displayID
    }

    enum CodingKeys: String, CodingKey {
        case intervalSeconds = "interval_seconds"
        case launchAtLogin = "launch_at_login"
        case displayID = "display_id"
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intervalSeconds, forKey: .intervalSeconds)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(displayID, forKey: .displayID)
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
