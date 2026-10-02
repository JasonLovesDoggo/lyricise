import Foundation
import Testing

@testable import LyriciseCore

@MainActor struct SettingsTests {
    @Test func createsDefaultsAndReportsInvalidInitialFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.toml")
        let settings = Settings(url: url)
        #expect(settings.error == nil)
        #expect(try AppConfig.parse(String(contentsOf: url, encoding: .utf8)) == settings.value)
        try "not valid TOML!".write(to: url, atomically: true, encoding: .utf8)
        let invalid = Settings(url: url)
        #expect(invalid.value == AppConfig())
        #expect(invalid.error != nil)
    }

    @Test func previewDoesNotWriteAndCommitSurvivesQueuedEvents() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        let original = try Data(contentsOf: settings.url)
        settings.preview(\.fontSize, to: 31)
        #expect(settings.value.fontSize == 31)
        #expect(try Data(contentsOf: settings.url) == original)
        settings.set(\.fontSize, to: 31)
        // Drain initial watch setup and the save's debounced event; neither may restore old values.
        try await Task.sleep(for: .milliseconds(400))
        #expect(settings.value.fontSize == 31)
        #expect(try AppConfig.parse(String(contentsOf: settings.url, encoding: .utf8)).fontSize == 31)
        #expect(settings.error == nil)
    }

    @Test func externalEditsRemainVisibleDuringPreviewAndSurviveCommit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        settings.preview(\.fontSize, to: 31)
        var external = AppConfig()
        external.fontSize = 14
        external.blurRadius = 42
        try external.serialized().write(to: settings.url, atomically: true, encoding: .utf8)
        settings.reload()
        #expect(settings.value.fontSize == 31)
        #expect(settings.value.blurRadius == 42)
        settings.set(\.fontSize, to: 31)
        external.fontSize = 31
        #expect(settings.value == external)
        #expect(try AppConfig.parse(String(contentsOf: settings.url, encoding: .utf8)) == external)
    }

    @Test func commitMergesExternalEditBeforeWatcherDeliversIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        var external = AppConfig()
        external.artworkVisibility = .always
        try external.serialized().write(to: settings.url, atomically: true, encoding: .utf8)
        settings.set(\.blurRadius, to: 50)
        #expect(settings.value.artworkVisibility == .always)
        #expect(settings.value.blurRadius == 50)
    }

    @Test func invalidFileIsNotOverwrittenByCommit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        let accepted = settings.value
        settings.preview(\.fontSize, to: 31)
        let invalid = "[appearance]\nfont_size = -1"
        try invalid.write(to: settings.url, atomically: true, encoding: .utf8)
        settings.reload()
        #expect(settings.value.fontSize == 31)
        #expect(settings.error != nil)
        settings.set(\.fontSize, to: 31)
        #expect(settings.value == accepted)
        #expect(settings.error != nil)
        #expect(try String(contentsOf: settings.url, encoding: .utf8) == invalid)
    }

    @Test func failedWriteRollsBackPreview() throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        let accepted = settings.value
        settings.preview(\.blurRadius, to: 80)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        settings.set(\.blurRadius, to: 80)
        #expect(settings.error != nil)
        #expect(settings.value == accepted)
        #expect(try AppConfig.parse(String(contentsOf: settings.url, encoding: .utf8)) == accepted)
    }

    @Test func watchesReplacementsInPlaceWritesAndInvalidRecovery() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        try "[appearance]\nfont_size = 30".write(to: settings.url, atomically: true, encoding: .utf8)
        try await waitUntil { settings.value.fontSize == 30 }
        try "[appearance]\nfont_size = 32".write(to: settings.url, atomically: false, encoding: .utf8)
        try await waitUntil { settings.value.fontSize == 32 }
        try "invalid TOML!".write(to: settings.url, atomically: true, encoding: .utf8)
        try await waitUntil { settings.error != nil }
        #expect(settings.value.fontSize == 32)
        try "[appearance]\nfont_size = 33".write(to: settings.url, atomically: true, encoding: .utf8)
        try await waitUntil { settings.value.fontSize == 33 && settings.error == nil }
    }

    @Test func rejectsOversizedAndNonUTF8FilesWithoutReplacingAcceptedSettings() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = Settings(url: directory.appendingPathComponent("config.toml"))
        let accepted = settings.value
        for data in [Data(repeating: 32, count: 256 * 1024 + 1), Data([0xFF])] {
            try data.write(to: settings.url, options: .atomic)
            settings.reload()
            #expect(settings.error != nil)
            #expect(settings.value == accepted)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}
