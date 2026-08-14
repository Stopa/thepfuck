import Foundation
import ThepfuckCore

func processRunnerTests() -> [TestCase] {
    [
        TestCase(name: "ProcessRunner delivers exact stdin") {
            let result = try ProcessRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/bin/cat"),
                stdin: Data("hello ü\n".utf8),
                timeout: 2
            ))
            try expectEqual(result.stdout, "hello ü\n")
            try expectEqual(result.stderr, "")
            try expectEqual(result.status, 0)
            try expectEqual(result.timedOut, false)
        },
        TestCase(name: "ProcessRunner keeps stdout stderr and status") {
            let result = try ProcessRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf out; printf err >&2; exit 7"],
                timeout: 2
            ))
            try expectEqual(result.stdout, "out")
            try expectEqual(result.stderr, "err")
            try expectEqual(result.status, 7)
        },
        TestCase(name: "ProcessRunner can combine stdout and stderr") {
            let result = try ProcessRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf out; printf err >&2"],
                combineOutput: true,
                timeout: 2
            ))
            try expectEqual(result.stdout, "outerr")
            try expectEqual(result.stderr, "")
        },
        TestCase(name: "ProcessRunner passes environment") {
            let result = try ProcessRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf %s \"$THEPFUCK_TEST_VALUE\""],
                environment: ["THEPFUCK_TEST_VALUE": "visible"],
                timeout: 2
            ))
            try expectEqual(result.stdout, "visible")
        },
        TestCase(name: "ProcessRunner terminates timed out command") {
            let start = Date()
            let result = try ProcessRunner.run(.init(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.1
            ))
            try expectEqual(result.timedOut, true)
            try expectLessThan(Date().timeIntervalSince(start), 2)
        },
        TestCase(name: "ProcessRunner reports launch failure") {
            do {
                _ = try ProcessRunner.run(.init(
                    executableURL: URL(fileURLWithPath: "/definitely/missing"),
                    timeout: 1
                ))
                throw TestFailure(description: "expected launch failure")
            } catch is ProcessRunnerError {
                // Expected typed boundary error.
            }
        },
    ]
}
