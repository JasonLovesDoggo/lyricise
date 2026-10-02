import Foundation

/// Input rules shared by the numeric controls in quick settings.
public enum NumericSettingInput {
    case fontSize
    case blur

    public var label: String {
        switch self {
        case .fontSize: "Font size in points"
        case .blur: "Blur intensity"
        }
    }

    public var help: String {
        switch self {
        case .fontSize: "Click to enter a size from 10 to 72 pt"
        case .blur: "Click to enter an intensity from 0 to 100, or Off"
        }
    }

    public func parse(_ input: String) -> Double? {
        var number = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if self == .blur && number == "off" { return 0 }
        if self == .fontSize && number.hasSuffix("pt") {
            number = String(number.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let value = Double(number), value.isFinite else { return nil }
        switch self {
        case .fontSize:
            return (10...72).contains(value) ? value : nil
        case .blur:
            return (0...100).contains(value) && value.rounded() == value ? value : nil
        }
    }

    public func display(_ value: Double) -> String {
        if self == .blur && value == 0 { return "Off" }
        let number = String(value)
        let compact = number.hasSuffix(".0") ? String(number.dropLast(2)) : number
        return self == .fontSize ? compact + "pt" : compact
    }
}
