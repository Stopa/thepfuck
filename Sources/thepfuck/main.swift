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

        let service = CorrectionService(
            capturer: ShellCommandCapturer(),
            suggester: ApfelClient()
        )
        let correction = try service.correct(
            command: command,
            shell: options.shell,
            shellPath: options.shellPath,
            aliasDefinitions: options.readHistory
                ? ProcessInfo.processInfo.environment[
                    ShellIntegration.capturedAliasesEnvironmentVariable
                ]
                : nil,
            commandTimeout: options.commandTimeout
        )

        if !options.yes {
            guard try confirm(correction) else {
                throw InteractionError.cancelled
            }
        }

        if options.readHistory {
            // The generated shell function captures stdout in order to eval it,
            // so mirror an auto-accepted command to stderr for visibility.
            if options.yes {
                writeStderr("\(correction)\n")
            }
            print(correction)
            return
        }

        Darwin.exit(try execute(correction, shellPath: options.shellPath))
    }

    private static func confirm(_ correction: String) throws -> Bool {
        let colorsEnabled = ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && Darwin.isatty(FileHandle.standardError.fileDescriptor) == 1
        let enter = colorsEnabled ? "\u{001B}[32menter\u{001B}[0m" : "enter"
        let cancel = colorsEnabled ? "\u{001B}[31mctrl+c\u{001B}[0m" : "ctrl+c"
        writeStderr("\(correction) [\(enter)/\(cancel)] ")
        guard let tty = FileHandle(forReadingAtPath: "/dev/tty") else {
            writeStderr("\n")
            throw InteractionError.noTTY
        }
        defer { try? tty.close() }
        var bytes: [UInt8] = []
        while bytes.count < 64 {
            var byte: UInt8 = 0
            let count = Darwin.read(tty.fileDescriptor, &byte, 1)
            guard count >= 0 else {
                throw InteractionError.ttyReadFailed(String(cString: strerror(errno)))
            }
            if count == 0 || byte == 10 || byte == 13 {
                break
            }
            bytes.append(byte)
        }
        let answer = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return answer.isEmpty
    }

    private static func execute(_ correction: String, shellPath: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", correction]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            throw InteractionError.executionFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            return 128 + process.terminationStatus
        }
        return process.terminationStatus
    }
}

private enum InteractionError: Error {
    case noTTY
    case ttyReadFailed(String)
    case cancelled
    case executionFailed(String)
}

private let helpText = """
thepfuck — fix the previous shell command with apfel's on-device AI

SETUP
  eval "$(thepfuck --alias)"              Define `fuck` for zsh or Bash
  eval "$(thepfuck --alias oops)"         Use a custom function name

USAGE
  fuck                                    Suggest, confirm, and run a correction
  fuck --yes                              Run the suggestion without confirmation
  thepfuck --command <text>                Correct and run an explicit command

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
    case InteractionError.ttyReadFailed(let detail):
        return "could not read confirmation from the terminal: \(detail)"
    case InteractionError.cancelled:
        return "aborted"
    case InteractionError.executionFailed(let detail):
        return "could not execute the correction: \(detail)"
    default:
        return String(describing: error)
    }
}
