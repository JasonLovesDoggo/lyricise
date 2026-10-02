import Testing

@testable import LyriciseCore

@Suite("Font size input")
struct FontSizeInputTests {
    @Test(arguments: ["20", "20pt", " 20 PT ", "20.0 pt"])
    func acceptsPoints(_ input: String) {
        #expect(FontSizeInput.parse(input) == 20)
    }

    @Test(arguments: [10.0, 19.25, 20.125, 72.0])
    func preservesFractionalSizesAndBounds(_ size: Double) {
        #expect(FontSizeInput.parse(FontSizeInput.display(size)) == size)
    }

    @Test(arguments: ["", "pt", "twenty", "20px", "20ptpt", "9.99", "72.01", "nan", "inf", "-inf"])
    func rejectsInvalidInput(_ input: String) {
        #expect(FontSizeInput.parse(input) == nil)
    }

    @Test func displaysCompactPointSuffix() {
        #expect(FontSizeInput.display(19) == "19pt")
        #expect(FontSizeInput.display(19.25) == "19.25pt")
    }
}
