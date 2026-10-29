import Foundation
import ServiceManagement

public struct LoginItemError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public struct SystemLoginItem: LoginItemManaging {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LoginItemError(message: error.localizedDescription)
        }
    }
}

/// Migre l'ancien LaunchAgent de la version Python vers un element de connexion natif.
public struct LegacyLaunchAgentMigrator {
    public static var defaultPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.pudeldoodle.mousemover.plist")
    }

    let plistURL: URL
    let loginItem: LoginItemManaging
    let unload: (URL) -> Void

    public init(plistURL: URL = LegacyLaunchAgentMigrator.defaultPlistURL,
                loginItem: LoginItemManaging = SystemLoginItem(),
                unload: @escaping (URL) -> Void = LegacyLaunchAgentMigrator.launchctlUnload) {
        self.plistURL = plistURL
        self.loginItem = loginItem
        self.unload = unload
    }

    /// Renvoie `true` si l'ancien LaunchAgent a ete remplace. Ne touche a rien si l'enregistrement echoue.
    @discardableResult
    public func migrateIfNeeded() -> Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }
        do {
            try loginItem.setEnabled(true)
        } catch {
            Log.core.error("Migration du LaunchAgent impossible: \(String(describing: error))")
            return false
        }
        unload(plistURL)
        try? FileManager.default.removeItem(at: plistURL)
        return true
    }

    public static func launchctlUnload(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
