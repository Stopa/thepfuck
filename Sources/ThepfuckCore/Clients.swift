import Foundation

public struct ShellCommandCapturer: CommandCapturing, Sendable {
    public init() {}

    public func capture(
        command: String,
        shellPath: String,
        timeout: TimeInterval
    ) throws -> CommandCapture {
        // Keep a noisy failed command from filling disk before the time limit.
        // `ulimit -f` is supported by both zsh and Bash; 256 blocks keeps enough
        // diagnostic tail for the prompt while bounding the temporary file.
        // Pass the command as $1 rather than interpolating it into this script.
        let captureScript = "ulimit -f 256 || exit $?\neval \"$1\""
        let result = try ProcessRunner.run(.init(
            executableURL: URL(fileURLWithPath: shellPath),
            arguments: ["-lc", captureScript, "thepfuck-capture", command],
            currentDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            combineOutput: true,
            timeout: timeout
        ))
        return CommandCapture(
            output: result.stdout,
            status: result.status,
            timedOut: result.timedOut
        )
    }
}

public enum ApfelClientError: Error, Equatable, Sendable {
    case notFound
    case timedOut
    case failed(status: Int32, message: String)
}

public struct ApfelClient: CorrectionSuggesting, Sendable {
    private let environment: [String: String]
    private let timeout: TimeInterval

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 120
    ) {
        self.environment = environment
        self.timeout = timeout
    }

    public func suggest(request: String, systemPrompt: String) throws -> String {
        guard let executable = ExecutableResolver.find("apfel", environment: environment) else {
            throw ApfelClientError.notFound
        }
        let result = try ProcessRunner.run(.init(
            executableURL: executable,
            arguments: ["-q", "--code", "-s", systemPrompt],
            stdin: Data(request.utf8),
            environment: environment,
            timeout: timeout
        ))
        guard !result.timedOut else {
            throw ApfelClientError.timedOut
        }
        guard result.status == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ApfelClientError.failed(status: result.status, message: message)
        }
        return result.stdout
    }
}

public enum ExecutableResolver {
    public static func find(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name)
                ? URL(fileURLWithPath: name)
                : nil
        }
        for directory in environment["PATH", default: ""].split(separator: ":", omittingEmptySubsequences: false) {
            let base = directory.isEmpty ? "." : String(directory)
            let candidate = URL(fileURLWithPath: base).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
