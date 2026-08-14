import Foundation

public struct CLIOptions: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case alias
        case correct
        case help
        case version
    }

    public let mode: Mode
    public let aliasName: String
    public let shell: ShellKind
    public let shellPath: String
    public let readHistory: Bool
    public let command: String?
    public let yes: Bool
    public let commandTimeout: TimeInterval

    public static func parse(
        arguments: [String],
        environment: [String: String]
    ) throws -> CLIOptions {
        var mode: Mode = .correct
        var aliasName = "fuck"
        var explicitShell: String?
        var readHistory = false
        var command: String?
        var yes = false
        var commandTimeout: TimeInterval = 3
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw CLIOptionsError.missingValue(option)
            }
            return arguments[valueIndex]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--alias":
                mode = .alias
                if index + 1 < arguments.count,
                   !arguments[index + 1].hasPrefix("-") {
                    aliasName = arguments[index + 1]
                    index += 1
                }
            case "--alias-name":
                aliasName = try value(after: argument)
                index += 1
            case "--shell":
                explicitShell = try value(after: argument)
                index += 1
            case "--history":
                readHistory = true
            case "--command":
                command = try value(after: argument)
                index += 1
            case "-y", "--yes", "--yeah", "--hard":
                yes = true
            case "--timeout":
                let raw = try value(after: argument)
                guard let parsed = Double(raw), parsed.isFinite, parsed > 0 else {
                    throw CLIOptionsError.invalidTimeout(raw)
                }
                commandTimeout = parsed
                index += 1
            case "-h", "--help":
                mode = .help
            case "-v", "--version":
                mode = .version
            default:
                throw CLIOptionsError.unknownOption(argument)
            }
            index += 1
        }

        if readHistory && command != nil {
            throw CLIOptionsError.conflictingCommandSources
        }
        if mode == .correct && !readHistory && command == nil {
            throw CLIOptionsError.noCommandSource
        }

        if mode == .help || mode == .version {
            return CLIOptions(
                mode: mode,
                aliasName: aliasName,
                shell: .zsh,
                shellPath: "/bin/zsh",
                readHistory: readHistory,
                command: command,
                yes: yes,
                commandTimeout: commandTimeout
            )
        }

        let environmentShellPath = environment["SHELL", default: ""]
        let shell: ShellKind
        let shellPath: String
        if let explicitShell {
            guard let parsed = ShellKind(rawValue: explicitShell) else {
                throw ShellIntegrationError.unsupportedShell(explicitShell)
            }
            shell = parsed
            if URL(fileURLWithPath: environmentShellPath).lastPathComponent == parsed.rawValue {
                shellPath = environmentShellPath
            } else {
                shellPath = "/bin/\(parsed.rawValue)"
            }
        } else {
            shell = try ShellKind.detect(from: environmentShellPath)
            shellPath = environmentShellPath
        }

        return CLIOptions(
            mode: mode,
            aliasName: aliasName,
            shell: shell,
            shellPath: shellPath,
            readHistory: readHistory,
            command: command,
            yes: yes,
            commandTimeout: commandTimeout
        )
    }
}

public enum CLIOptionsError: Error, Equatable, Sendable {
    case missingValue(String)
    case invalidTimeout(String)
    case conflictingCommandSources
    case unknownOption(String)
    case noCommandSource
}
