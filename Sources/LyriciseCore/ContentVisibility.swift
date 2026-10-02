/// When song details or artwork appear in the lyrics window.
public enum ContentVisibility: String, Codable, CaseIterable, Sendable {
    case never, hover, always

    public var label: String {
        switch self {
        case .never: "Never"
        case .hover: "On hover"
        case .always: "Always"
        }
    }

    public func isVisible(hovering: Bool) -> Bool {
        self == .always || (self == .hover && hovering)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let legacy = try? container.decode(Bool.self) {
            self = legacy ? .always : .never
        } else {
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Use never, hover, or always.")
            }
            self = value
        }
    }
}
