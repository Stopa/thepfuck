import Foundation

public struct CommandCapture: Equatable, Sendable {
    public let output: String
    public let status: Int32
    public let timedOut: Bool

    public init(output: String, status: Int32, timedOut: Bool) {
        self.output = output
        self.status = status
        self.timedOut = timedOut
    }
}

public protocol CommandCapturing: Sendable {
    func capture(
        command: String,
        shellPath: String,
        timeout: TimeInterval
    ) throws -> CommandCapture
}

public protocol CorrectionSuggesting: Sendable {
    func suggest(request: String, systemPrompt: String) throws -> String
}

public enum CorrectionServiceError: Error, Equatable, Sendable {
    case commandTimedOut
}

public struct CorrectionService: Sendable {
    private let capturer: any CommandCapturing
    private let suggester: any CorrectionSuggesting

    public init(
        capturer: any CommandCapturing,
        suggester: any CorrectionSuggesting
    ) {
        self.capturer = capturer
        self.suggester = suggester
    }

    public func correct(
        command: String,
        shell: ShellKind,
        shellPath: String,
        aliasDefinitions: String? = nil,
        commandTimeout: TimeInterval
    ) throws -> String {
        let expandedCommand = AliasExpander.expand(
            command: command,
            definitions: aliasDefinitions ?? "",
            shell: shell
        )
        let capture = try capturer.capture(
            command: expandedCommand,
            shellPath: shellPath,
            timeout: commandTimeout
        )
        guard !capture.timedOut else {
            throw CorrectionServiceError.commandTimedOut
        }
        let request = try CorrectionRequest.prompt(
            command: expandedCommand,
            output: capture.output,
            shell: shell.rawValue
        )
        let response = try suggester.suggest(
            request: request,
            systemPrompt: CorrectionRequest.systemPrompt
        )
        return try CandidateValidator.validate(response)
    }
}
