import Foundation

public struct DefaultNoopDatabaseLocator {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func candidatePaths() -> [String] {
        var paths: [String] = []

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("OpenWhoop/whoop.sqlite").path)
            paths.append(appSupport.appendingPathComponent("Noop/whoop.sqlite").path)
        }

        if let home = ProcessInfo.processInfo.environment["HOME"] {
            paths.append(home + "/Library/Application Support/OpenWhoop/whoop.sqlite")
            paths.append(home + "/Library/Application Support/Noop/whoop.sqlite")
            paths.append(home + "/Library/Containers/com.noopapp.noop/Data/Library/Application Support/OpenWhoop/whoop.sqlite")
        }

        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    public func firstExistingDatabasePath() -> String? {
        candidatePaths().first { fileManager.fileExists(atPath: $0) }
    }
}
