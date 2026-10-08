import Foundation

public struct ConfigurationLoadResult: Sendable {
    public let configuration: AppConfiguration
    public let warning: String?
}

public struct ConfigurationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> ConfigurationLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .init(configuration: .init(), warning: nil)
        }
        let data = try Data(contentsOf: url)
        let decoded: AppConfiguration
        do { decoded = try JSONDecoder().decode(AppConfiguration.self, from: data).validated() }
        catch {
            // Preserve the original bytes before a future save replaces this file.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("invalid-\(UUID().uuidString).json")
            try data.write(to: backup, options: .atomic)
            return .init(configuration: .init(), warning:
                "설정을 읽을 수 없어 기본값으로 시작했습니다. 원본은 \(backup.lastPathComponent)에 보관했습니다.")
        }
        let migrated = try decoded.migratedToCurrent().validated()
        if migrated != decoded {
            let backup = url.deletingPathExtension().appendingPathExtension("before-gestures-\(UUID().uuidString).json")
            try data.write(to: backup, options: .atomic)
            try save(migrated)
            return .init(configuration: migrated, warning:
                "휠 버튼 제스처를 적용했습니다. 옆면 버튼의 데스크톱 매핑을 해제했고, 이전 설정은 \(backup.lastPathComponent)에 보관했습니다.")
        }
        return .init(configuration: migrated, warning: nil)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let valid = try configuration.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(valid).write(to: url, options: .atomic)
    }
}
