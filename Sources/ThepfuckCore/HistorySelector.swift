import Foundation

public enum HistorySelectionError: Error, Equatable, Sendable {
    case noCommand
}

public enum HistorySelector {
    public static func select(from history: String, alias: String) throws -> String {
        for rawLine in history.components(separatedBy: .newlines).reversed() {
            let command = rawLine.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty,
                  !isInvocation(command, of: alias),
                  !isInvocation(command, of: "thepfuck") else {
                continue
            }
            return command
        }
        throw HistorySelectionError.noCommand
    }

    private static func isInvocation(_ command: String, of executable: String) -> Bool {
        guard command.hasPrefix(executable) else { return false }
        let suffix = command.dropFirst(executable.count)
        return suffix.isEmpty || suffix.first?.isWhitespace == true
    }
}
