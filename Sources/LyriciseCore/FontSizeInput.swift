import Foundation

/// Accepts point sizes typed in quick settings, with an optional pt suffix.
public enum FontSizeInput {
    public static func parse(_ input: String) -> Double? {
        var number = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.lowercased().hasSuffix("pt") {
            number = String(number.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let size = Double(number), size.isFinite, (10...72).contains(size) else {
            return nil
        }
        return size
    }

    public static func display(_ size: Double) -> String {
        let number = String(size)
        return (number.hasSuffix(".0") ? String(number.dropLast(2)) : number) + "pt"
    }
}
