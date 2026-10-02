import Foundation
import Testing

@testable import LyriciseCore

@Suite("Numeric settings input")
struct NumericSettingInputTests {
    @Test(arguments: ["20", "20pt", " 20 PT ", "20.0 pt"])
    func acceptsPoints(_ input: String) {
        #expect(NumericSettingInput.fontSize.parse(input) == 20)
    }

    @Test(arguments: [10.0, 19.25, 20.125, 72.0])
    func preservesFractionalSizesAndBounds(_ size: Double) {
        #expect(NumericSettingInput.fontSize.parse(NumericSettingInput.fontSize.display(size)) == size)
    }

    @Test(arguments: ["", "pt", "twenty", "20px", "20ptpt", "9.99", "72.01", "nan", "inf", "-inf"])
    func rejectsInvalidInput(_ input: String) {
        #expect(NumericSettingInput.fontSize.parse(input) == nil)
    }

    @Test(arguments: ["0", "10", "100", " 25 "])
    func acceptsBlurIntensity(_ input: String) {
        #expect(NumericSettingInput.blur.parse(input) == Double(input.trimmingCharacters(in: .whitespaces)))
    }

    @Test(arguments: ["Off", " off ", "OFF"])
    func acceptsDisabledBlur(_ input: String) {
        #expect(NumericSettingInput.blur.parse(input) == 0)
    }

    @Test(arguments: ["-1", "101", "10.5", "20pt", "nan", "inf", ""])
    func rejectsInvalidBlur(_ input: String) {
        #expect(NumericSettingInput.blur.parse(input) == nil)
    }

    @Test func displaysBlurIntensity() {
        #expect(NumericSettingInput.blur.display(0) == "Off")
        #expect(NumericSettingInput.blur.display(20) == "20")
    }

    @Test func displaysCompactPointSuffix() {
        #expect(NumericSettingInput.fontSize.display(19) == "19pt")
        #expect(NumericSettingInput.fontSize.display(19.25) == "19.25pt")
    }
}
