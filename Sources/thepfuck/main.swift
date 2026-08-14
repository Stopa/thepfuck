import Foundation
import ThepfuckCore
import Darwin

private let version = "0.1.0"

@main
struct ThepfuckMain {
    static func main() {
        do {
            let options = try CLIOptions.parse(
                arguments: Array(CommandLine.arguments.dropFirst()),
                environment: ProcessInfo.processInfo.environment
            )
            switch options.mode {
            case .help:
                print(helpText)
            case .version:
                print("thepfuck \(version)")
            case .alias:
                print(
                    try ShellIntegration.render(
                        shell: options.shell,
                        alias: options.aliasName
                    ),
                    terminator: ""
                )
            case .correct:
                try runCorrection(options)
            }
        } catch {
            writeStderr("thepfuck: \(message(for: error))\n")
            Darwin.exit(exitCode(for: error))
        }
    }

    private static func runCorrection(_ options: CLIOptions) throws {
        let command: String
        if options.readHistory {
            let data = (try? FileHandle.standardInput.readToEnd()) ?? Data()
            let history = String(decoding: data, as: UTF8.self)
            command = try HistorySelector.select(from: history, alias: options.aliasName)
        } else if let explicit = options.command {
            command = explicit
        } else {
            throw CLIOptionsError.noCommandSource
        }

        writeStderr("thepfuck: finding a fix for: \(command)\n")
        let service = CorrectionService(
            capturer: ShellCommandCapturer(),
            suggester: ApfelClient()
        )
        let correction = try service.correct(
            command: command,
            shell: options.shell,
            shellPath: options.shellPath,
            commandTimeout: options.commandTimeout
        )

        if !options.yes {
            guard try confirm(correction) else {
                throw InteractionError.cancelled
            }
        } else if options.readHistory {
            // The generated shell function captures stdout in order to eval it,
            // so mirror the accepted command to stderr only for that path.
            writeStderr("\(correction)\n")
        }
        print(correction)
    }

    private static func confirm(_ correction: String) throws -> Bool {
        writeStderr("\(correction) [enter/y/N] ")
        guard let tty = FileHandle(forReadingAtPath: "/dev/tty") else {
            writeStderr("\n")
            throw InteractionError.noTTY
        }
        defer { try? tty.close() }
        let data = try tty.read(upToCount: 64) ?? Data()
        let answer = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return answer.isEmpty || answer == "y" || answer == "yes"
    }
}

private enum InteractionError: Error {
    case noTTY
    case cancelled
}

private let helpText = """
thepfuck — fix the previous shell command with apfel's on-device AI

SETUP
  eval "$(thepfuck --alias)"              Define `fuck` for zsh or Bash
  eval "$(thepfuck --alias oops)"         Use a custom function name

USAGE
  fuck                                    Suggest, confirm, and run a correction
  fuck --yes                              Run the suggestion without confirmation
  thepfuck --command <text>                Correct an explicit command

OPTIONS
  --alias [name]                          Print shell integration
  --shell <zsh|bash>                      Select shell explicitly
  --command <text>                        Command to diagnose
  --timeout <seconds>                     Failed-command re-run timeout (default: 3)
  -y, --yes                               Skip confirmation (unsafe)
  -h, --help                              Show this help
  -v, --version                           Show version
"""

private func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

private func exitCode(for error: Error) -> Int32 {
    switch error {
    case is CLIOptionsError, is ShellIntegrationError:
        return 2
    case ApfelClientError.notFound:
        return 127
    default:
        return 1
    }
}

private func message(for error: Error) -> String {
    switch error {
    case CLIOptionsError.missingValue(let option):
        return "missing value for \(option)"
    case CLIOptionsError.invalidTimeout(let value):
        return "invalid timeout '\(value)'; expected a positive number"
    case CLIOptionsError.conflictingCommandSources:
        return "--history and --command cannot be used together"
    case CLIOptionsError.unknownOption(let option):
        return "unknown option '\(option)'; use --help"
    case CLIOptionsError.noCommandSource:
        return "no command provided; configure the shell function with `eval \"$(thepfuck --alias)\"`"
    case ShellIntegrationError.unsupportedShell(let shell):
        return "unsupported shell '\(shell)'; this version supports zsh and Bash"
    case ShellIntegrationError.invalidAlias(let alias):
        return "invalid alias name '\(alias)'"
    case HistorySelectionError.noCommand:
        return "no previous command found in shell history"
    case CorrectionServiceError.commandTimedOut:
        return "the previous command timed out while its error was being captured"
    case ApfelClientError.notFound:
        return "apfel was not found on PATH; install it from https://github.com/Arthur-Ficial/apfel"
    case ApfelClientError.timedOut:
        return "apfel timed out while generating a correction"
    case ApfelClientError.failed(let status, let detail):
        return detail.isEmpty ? "apfel failed with exit \(status)" : "apfel failed with exit \(status): \(detail)"
    case CandidateValidationError.empty:
        return "apfel returned no correction"
    case CandidateValidationError.containsNUL:
        return "apfel returned an invalid command containing a NUL byte"
    case CandidateValidationError.markdownFence:
        return "apfel returned an invalid fenced response"
    case ProcessRunnerError.launchFailed(let detail):
        return "could not run a subprocess: \(detail)"
    case ProcessRunnerError.temporaryFileFailed(let detail):
        return "could not capture subprocess output: \(detail)"
    case InteractionError.noTTY:
        return "confirmation requires an interactive terminal; inspect the suggestion there or pass --yes explicitly"
    case InteractionError.cancelled:
        return "aborted"
    default:
        return String(describing: error)
    }
}
