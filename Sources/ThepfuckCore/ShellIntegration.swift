import Foundation

public enum ShellKind: String, Equatable, Sendable {
    case zsh
    case bash

    public static func detect(from shellPath: String) throws -> ShellKind {
        guard !shellPath.isEmpty else {
            throw ShellIntegrationError.unsupportedShell("")
        }
        let name = URL(fileURLWithPath: shellPath).lastPathComponent
        guard let shell = ShellKind(rawValue: name) else {
            throw ShellIntegrationError.unsupportedShell(name)
        }
        return shell
    }
}

public enum ShellIntegrationError: Error, Equatable, Sendable {
    case unsupportedShell(String)
    case invalidAlias(String)
}

public enum ShellIntegration {
    public static let capturedAliasesEnvironmentVariable = "THEPFUCK_CAPTURED_ALIASES"

    public static func render(shell: ShellKind, alias: String) throws -> String {
        guard isValidAlias(alias) else {
            throw ShellIntegrationError.invalidAlias(alias)
        }

        let declaration = shell == .bash ? "function \(alias)()" : "\(alias)()"
        let historyInsertion = shell == .zsh
            ? "print -s -- \"$thepfuck_command\""
            : "history -s \"$thepfuck_command\""
        let recentHistory = shell == .zsh
            ? "fc -ln -10"
            : "HISTTIMEFORMAT= builtin history 10 | sed 's/^[[:space:]]*[0-9][0-9]*[[:space:]]*//'"
        let capturedAliases = "alias"
        return """
        \(declaration) {
          local thepfuck_aliases thepfuck_command thepfuck_status;
          thepfuck_aliases="$(\(capturedAliases))";
          thepfuck_command="$(\(recentHistory) | \(capturedAliasesEnvironmentVariable)="$thepfuck_aliases" command thepfuck --history --shell \(shell.rawValue) --alias-name \(alias) "$@")";
          thepfuck_status=$?;
          if [ "$thepfuck_status" -ne 0 ]; then
            return "$thepfuck_status";
          fi;
          if [ -z "$thepfuck_command" ]; then
            return 1;
          fi;
          \(historyInsertion);
          eval "$thepfuck_command";
        }
        """ + "\n"
    }

    private static func isValidAlias(_ alias: String) -> Bool {
        guard let first = alias.first, first.isLetter || first == "_" else {
            return false
        }
        return alias.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
