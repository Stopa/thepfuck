import Foundation
import ThepfuckCore

func clientTests() -> [TestCase] {
    [
        TestCase(name: "ShellCommandCapturer combines output and preserves status") {
            let capture = try ShellCommandCapturer().capture(
                command: "printf out; printf err >&2; exit 9",
                shellPath: "/bin/sh",
                timeout: 2
            )
            try expectEqual(capture.output, "outerr")
            try expectEqual(capture.status, 9)
            try expectEqual(capture.timedOut, false)
        },
        TestCase(name: "ShellCommandCapturer bounds a slow command") {
            let capture = try ShellCommandCapturer().capture(
                command: "sleep 5",
                shellPath: "/bin/sh",
                timeout: 0.1
            )
            try expectEqual(capture.timedOut, true)
        },
        TestCase(name: "ShellCommandCapturer bounds child output files") {
            let capture = try ShellCommandCapturer().capture(
                command: "ulimit -f",
                shellPath: "/bin/sh",
                timeout: 2
            )
            try expectEqual(capture.output.trimmingCharacters(in: .whitespacesAndNewlines), "256")
        },
        TestCase(name: "ApfelClient invokes quiet code mode and pipes request") {
            try withTemporaryDirectory { directory in
                let argsFile = directory.appendingPathComponent("args")
                let inputFile = directory.appendingPathComponent("input")
                try writeExecutable(
                    at: directory.appendingPathComponent("apfel"),
                    contents: """
                    #!/bin/sh
                    printf '%s\n' "$@" > "$APFEL_ARGS_FILE"
                    /bin/cat > "$APFEL_INPUT_FILE"
                    printf 'git status\n'
                    """
                )
                let client = ApfelClient(
                    environment: [
                        "PATH": directory.path,
                        "APFEL_ARGS_FILE": argsFile.path,
                        "APFEL_INPUT_FILE": inputFile.path,
                    ],
                    timeout: 2
                )
                let response = try client.suggest(request: "payload ü", systemPrompt: "system")
                try expectEqual(response, "git status\n")
                try expectEqual(try String(contentsOf: inputFile, encoding: .utf8), "payload ü")
                let args = try String(contentsOf: argsFile, encoding: .utf8)
                try expectEqual(args, "-q\n--code\n-s\nsystem\n")
            }
        },
        TestCase(name: "ApfelClient reports missing executable") {
            let client = ApfelClient(environment: ["PATH": "/definitely/missing"], timeout: 1)
            try expectThrows(ApfelClientError.notFound) {
                _ = try client.suggest(request: "x", systemPrompt: "y")
            }
        },
        TestCase(name: "ApfelClient never turns failure stderr into response") {
            try withTemporaryDirectory { directory in
                try writeExecutable(
                    at: directory.appendingPathComponent("apfel"),
                    contents: "#!/bin/sh\nprintf 'model unavailable' >&2\nexit 5\n"
                )
                let client = ApfelClient(environment: ["PATH": directory.path], timeout: 2)
                do {
                    _ = try client.suggest(request: "x", systemPrompt: "y")
                    throw TestFailure(description: "expected apfel failure")
                } catch let error as ApfelClientError {
                    try expectEqual(error, .failed(status: 5, message: "model unavailable"))
                }
            }
        },
        TestCase(name: "ApfelClient reports timeout") {
            try withTemporaryDirectory { directory in
                try writeExecutable(
                    at: directory.appendingPathComponent("apfel"),
                    contents: "#!/bin/sh\nexec /bin/sleep 5\n"
                )
                let client = ApfelClient(environment: ["PATH": directory.path], timeout: 0.1)
                try expectThrows(ApfelClientError.timedOut) {
                    _ = try client.suggest(request: "x", systemPrompt: "y")
                }
            }
        },
    ]
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("thepfuck-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func writeExecutable(at url: URL, contents: String) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
