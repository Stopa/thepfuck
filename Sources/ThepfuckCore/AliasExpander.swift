import Foundation

public enum AliasExpander {
    public static func expand(
        command: String,
        definitions: String,
        shell: ShellKind
    ) -> String {
        guard !command.isEmpty, !definitions.isEmpty else { return command }

        let start = command.firstIndex { !$0.isWhitespace } ?? command.endIndex
        guard start != command.endIndex else { return command }
        let end = command[start...].firstIndex { $0.isWhitespace } ?? command.endIndex
        let name = String(command[start..<end])
        guard let replacement = parse(definitions: definitions, shell: shell)[name] else {
            return command
        }

        return String(command[..<start]) + replacement + String(command[end...])
    }

    private static func parse(definitions: String, shell: ShellKind) -> [String: String] {
        var aliases: [String: String] = [:]
        for rawLine in definitions.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("alias ") {
                line.removeFirst("alias ".count)
            } else if shell == .bash {
                continue
            }

            // Ignore zsh global/suffix alias declarations such as `alias -g`.
            guard !line.hasPrefix("-"), let equals = line.firstIndex(of: "=") else {
                continue
            }
            let name = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(where: { $0.isWhitespace }) else {
                continue
            }
            let rawValue = String(line[line.index(after: equals)...])
            aliases[unquote(name)] = unquote(rawValue)
        }
        return aliases
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              first == value.last,
              first == "'" || first == "\"" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
