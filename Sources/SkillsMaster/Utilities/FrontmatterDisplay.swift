import Foundation

struct FrontmatterField: Equatable {
    let key: String
    let value: String
}

enum FrontmatterDisplay {

    static func fields(from frontmatterText: String) -> [FrontmatterField] {
        let lines = frontmatterText.components(separatedBy: .newlines)
        var fields: [FrontmatterField] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || line.hasPrefix(" ")
                || line.hasPrefix("\t") {
                index += 1
                continue
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(line[line.index(after: colonIndex)...])
            let trimmedRemainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedRemainder.isEmpty || isBlockScalarIndicator(trimmedRemainder) {
                index += 1
                var blockLines: [String] = []

                while index < lines.count {
                    let next = lines[index]
                    if next.hasPrefix(" ") || next.hasPrefix("\t") || next.isEmpty {
                        blockLines.append(next)
                        index += 1
                    } else {
                        break
                    }
                }

                fields.append(FrontmatterField(
                    key: key,
                    value: normalizeIndentedBlock(blockLines)
                ))
                continue
            }

            fields.append(FrontmatterField(key: key, value: trimmedRemainder))
            index += 1
        }

        return fields
    }

    static func value(for key: String, in frontmatterText: String) -> String? {
        fields(from: frontmatterText)
            .first { $0.key == key }?
            .value
    }

    static func extraFields(
        from frontmatterText: String,
        excluding excludedKeys: Set<String>
    ) -> [FrontmatterField] {
        fields(from: frontmatterText).filter { field in
            guard !excludedKeys.contains(field.key) else { return false }

            if field.key == "metadata" {
                return shouldDisplayMetadataField(field.value)
            }

            return !field.value.isEmpty
        }
    }

    private static func isBlockScalarIndicator(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        guard first == ">" || first == "|" else { return false }
        return text.dropFirst().allSatisfy { $0 == "-" || $0 == "+" || $0.isNumber }
    }

    private static func normalizeIndentedBlock(_ lines: [String]) -> String {
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let minIndent = nonEmptyLines
            .map(\.leadingWhitespaceCount)
            .min() ?? 0

        return lines
            .map { line in
                guard !line.isEmpty else { return "" }
                return String(line.dropFirst(min(minIndent, line.count)))
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldDisplayMetadataField(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return true
        }

        let nestedKeys = trimmed
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, let colonIndex = raw.firstIndex(of: ":") else { return nil }
                return String(raw[..<colonIndex])
            }

        if nestedKeys.isEmpty {
            return true
        }

        return !Set(nestedKeys).isSubset(of: ["author", "version"])
    }
}

private extension String {
    var leadingWhitespaceCount: Int {
        prefix { $0 == " " || $0 == "\t" }.count
    }
}
