import Foundation
import TOML

/// Uses the TOML parser to identify complete statements and their decoded key paths.
/// Only a scalar value is replaced; all other source bytes, including comments, remain intact.
struct ConfigDocument {
    static func updating(_ source: String, from old: AppConfig, to updated: AppConfig) throws -> String {
        let before = try old.serialized().components(separatedBy: "\n")
        let after = try updated.serialized().components(separatedBy: "\n")
        var section = ""
        var edits: [(path: [String], value: String)] = []
        for (original, replacement) in zip(before, after) {
            if replacement.hasPrefix("[") { section = String(replacement.dropFirst().dropLast()) }
            if original != replacement, let equal = replacement.firstIndex(of: "=") {
                edits.append(([section, replacement[..<equal].trimmingCharacters(in: .whitespaces)],
                              replacement[replacement.index(after: equal)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        var result = source
        for edit in edits { result = try replacing(result, path: edit.path, value: edit.value) }
        guard (try? AppConfig.parse(result)) == updated else { throw EditError.unsupported }
        return result
    }

    private static func replacing(_ source: String, path: [String], value: String) throws -> String {
        var context: [String] = []
        var insertion = source.startIndex
        var offset = source.startIndex
        while offset < source.endIndex {
            let start = offset
            let (statement, decoded) = try readStatement(source, offset: &offset)
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                // Array-of-table headers cannot describe a supported setting table.
                context = trimmed.hasPrefix("[[") ? ["<array>"] : decoded.leaves.first ?? []
                if context == [path[0]] { insertion = offset }
                continue
            }
            if decoded.leaves.isEmpty { continue }
            let paths = decoded.leaves.map { context + $0 }
            if paths.contains(path) {
                // Inline tables and multiline target values are left to the config editor.
                guard paths.count == 1, let equal = unquoted("=", in: statement) else {
                    throw EditError.unsupported
                }
                let suffix = String(statement[statement.index(after: equal)...])
                let comment = unquoted("#", in: suffix) ?? suffix.endIndex
                let scalar = suffix[..<comment].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !scalar.hasPrefix("{"), !scalar.contains("\n"),
                      let localRange = statement.range(of: scalar, range: statement.index(after: equal)..<statement.endIndex)
                else { throw EditError.unsupported }
                let lower = source.index(start, offsetBy: statement.distance(from: statement.startIndex, to: localRange.lowerBound))
                let upper = source.index(lower, offsetBy: scalar.count)
                var result = source
                result.replaceSubrange(lower..<upper, with: value)
                return result
            }
            if context == [path[0]] { insertion = offset }
        }
        // Insert into the existing table, or use a root dotted key before any table headers.
        let assignment = insertion == source.startIndex ? path.joined(separator: ".") : path[1]
        let prefix = insertion > source.startIndex && !source[source.index(before: insertion)].isNewline ? "\n" : ""
        var result = source
        result.insert(contentsOf: prefix + assignment + " = " + value + "\n", at: insertion)
        return result
    }

    private static func readStatement(_ source: String, offset: inout String.Index) throws -> (String, Paths) {
        var statement = ""
        // Bound work on multiline values. Unusual documents can always be edited manually.
        for _ in 0..<32 {
            let end = source[offset...].firstIndex(where: \.isNewline).map { source.index(after: $0) } ?? source.endIndex
            statement += source[offset..<end]
            offset = end
            guard statement.utf8.count <= 16 * 1024 else { throw EditError.unsupported }
            if let parsed = try? TOMLDecoder().decode(Paths.self, from: statement) { return (statement, parsed) }
            if offset == source.endIndex { break }
        }
        throw EditError.unsupported
    }

    /// Locates punctuation outside a single-line quoted key/value. TOML validates syntax.
    private static func unquoted(_ character: Character, in source: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        for index in source.indices {
            let current = source[index]
            if escaped { escaped = false; continue }
            if quote == "\"", current == "\\" { escaped = true; continue }
            if let delimiter = quote {
                if current == delimiter { quote = nil }
            } else if current == "\"" || current == "'" {
                quote = current
            } else if current == character { return index }
        }
        return nil
    }

    private struct Paths: Decodable {
        var leaves: [[String]] = []
        init(from decoder: any Decoder) throws {
            guard let container = try? decoder.container(keyedBy: Key.self) else { return }
            for key in container.allKeys {
                let child = try container.decode(Paths.self, forKey: key)
                leaves += child.leaves.isEmpty ? [[key.stringValue]] : child.leaves.map { [key.stringValue] + $0 }
            }
        }
        struct Key: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
    }

    private enum EditError: LocalizedError {
        case unsupported
        var errorDescription: String? {
            "This TOML layout cannot be changed safely in Quick Settings. Use Open Config to edit the setting; the file was left unchanged."
        }
    }
}
