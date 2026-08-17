import Foundation
import ThepfuckCore

func correctionServiceTests() -> [TestCase] {
    [
        TestCase(name: "CorrectionService captures then requests correction") {
            let capturer = MockCommandCapturer(result: .init(
                output: "git: 'stats' is not a git command",
                status: 1,
                timedOut: false
            ))
            let suggester = MockCorrectionSuggester(response: "  git status\n")
            let service = CorrectionService(capturer: capturer, suggester: suggester)

            let correction = try service.correct(
                command: "g stats",
                shell: .zsh,
                shellPath: "/bin/zsh",
                aliasDefinitions: "g=git",
                commandTimeout: 3
            )

            try expectEqual(correction, "git status")
            try expectEqual(capturer.calls.count, 1)
            try expectEqual(capturer.calls.first?.command, "git stats")
            try expectEqual(capturer.calls.first?.shellPath, "/bin/zsh")
            try expectEqual(suggester.calls.count, 1)
            let request = try require(suggester.calls.first?.request, "missing request")
            try expectContains(request, "git stats")
            try expectContains(request, "not a git command")
            try expectEqual(suggester.calls.first?.systemPrompt, CorrectionRequest.systemPrompt)
        },
        TestCase(name: "CorrectionService does not call apfel after command timeout") {
            let capturer = MockCommandCapturer(result: .init(
                output: "",
                status: 15,
                timedOut: true
            ))
            let suggester = MockCorrectionSuggester(response: "anything")
            let service = CorrectionService(capturer: capturer, suggester: suggester)
            try expectThrows(CorrectionServiceError.commandTimedOut) {
                _ = try service.correct(
                    command: "slow",
                    shell: .bash,
                    shellPath: "/bin/bash",
                    commandTimeout: 0.1
                )
            }
            try expectEqual(suggester.calls.count, 0)
        },
        TestCase(name: "CorrectionService rejects invalid model response") {
            let capturer = MockCommandCapturer(result: .init(
                output: "failed",
                status: 1,
                timedOut: false
            ))
            let suggester = MockCorrectionSuggester(response: "  \n")
            let service = CorrectionService(capturer: capturer, suggester: suggester)
            try expectThrows(CandidateValidationError.empty) {
                _ = try service.correct(
                    command: "bad",
                    shell: .zsh,
                    shellPath: "/bin/zsh",
                    commandTimeout: 3
                )
            }
        },
    ]
}

private final class MockCommandCapturer: CommandCapturing, @unchecked Sendable {
    struct Call {
        let command: String
        let shellPath: String
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []
    private let result: CommandCapture

    init(result: CommandCapture) {
        self.result = result
    }

    func capture(
        command: String,
        shellPath: String,
        timeout: TimeInterval
    ) throws -> CommandCapture {
        calls.append(.init(
            command: command,
            shellPath: shellPath,
            timeout: timeout
        ))
        return result
    }
}

private final class MockCorrectionSuggester: CorrectionSuggesting, @unchecked Sendable {
    struct Call {
        let request: String
        let systemPrompt: String
    }

    private(set) var calls: [Call] = []
    private let response: String

    init(response: String) {
        self.response = response
    }

    func suggest(request: String, systemPrompt: String) throws -> String {
        calls.append(.init(request: request, systemPrompt: systemPrompt))
        return response
    }
}
