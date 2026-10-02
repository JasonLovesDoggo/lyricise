import Testing
@testable import LyriciseCore

@Test func configSerializationPreservesAllSettings() throws {
    var config = AppConfig()
    config.width = 618.5
    config.height = 244.5
    config.alwaysOnTop = false
    config.allSpaces = false
    config.rememberPosition = false
    config.background = "#102030"
    config.accent = "#AABBCC"
    config.text = "#FEDCBA"
    config.mutedText = "#654321"
    config.opacity = 0.42
    config.fontSize = 27.5
    config.padding = 23.5
    config.cornerRadius = 22.5
    config.blurRadius = 37
    config.showTrackTitle = false
    config.showArtwork = true
    config.followPlayback = false
    config.font = "A \"Quoted\" Font \\ Variant"
    config.offsetMS = -125.5
    let source = try config.serialized()
    #expect(try AppConfig.parse(source) == config)
    #expect(source.hasSuffix("\n"))
    #expect(try AppConfig.parse(AppConfig().serialized()) == AppConfig())
}

@Test func configSerializationRejectsInvalidProgrammaticChanges() {
    var config = AppConfig()
    config.opacity = 2
    #expect(throws: (any Error).self) { try config.serialized() }
}

@Test func artworkIsOptInAndIndependentOfTrackTitle() throws {
    #expect(AppConfig().showArtwork == false)
    #expect(try AppConfig.parse("[lyrics]\nshow_track_title = false").showArtwork == false)
    let config = try AppConfig.parse("[lyrics]\nshow_album_art = true\nshow_track_title = false")
    #expect(config.showArtwork)
    #expect(config.showTrackTitle == false)
}

@Test func cornerRadiusDefaultsAndBounds() throws {
    #expect(AppConfig().cornerRadius == 12)
    #expect(try AppConfig.parse("[appearance]\ncorner_radius = 0").cornerRadius == 0)
    #expect(try AppConfig.parse("[appearance]\ncorner_radius = 40").cornerRadius == 40)
    #expect(try AppConfig.parse("[appearance]\ncorner_radius = 17.5").cornerRadius == 17.5)
    for invalid in ["-0.1", "40.1", "nan", "inf"] {
        #expect(throws: (any Error).self) {
            try AppConfig.parse("[appearance]\ncorner_radius = \(invalid)")
        }
    }
}

@Test func blurIntensityDefaultsCompatibilityAndBounds() throws {
    #expect(AppConfig().blurRadius == 0)
    #expect(AppConfig().blur == false)
    #expect(try AppConfig.parse("").blurRadius == 0)
    #expect(try AppConfig.parse("[appearance]\nblur = true").blurRadius == 20)
    #expect(try AppConfig.parse("[appearance]\nblur = false").blurRadius == 0)
    for valid in [0, 17, 100] {
        let config = try AppConfig.parse("[appearance]\nblur = \(valid)")
        #expect(config.blurRadius == valid)
        let encoded = try config.serialized()
        #expect(try AppConfig.parse(encoded).blurRadius == valid)
        #expect(!encoded.contains("blur = true") && !encoded.contains("blur = false"))
    }
    for invalid in ["-1", "101", "17.5", "nan", "inf", "'20'"] {
        #expect(throws: (any Error).self) {
            try AppConfig.parse("[appearance]\nblur = \(invalid)")
        }
    }
}
