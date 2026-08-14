@preconcurrency import Foundation
import Darwin

public struct ProcessRequest: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let stdin: Data?
    public let environment: [String: String]?
    public let currentDirectoryURL: URL?
    public let combineOutput: Bool
    public let timeout: TimeInterval

    public init(
        executableURL: URL,
        arguments: [String] = [],
        stdin: Data? = nil,
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        combineOutput: Bool = false,
        timeout: TimeInterval
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.stdin = stdin
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.combineOutput = combineOutput
        self.timeout = timeout
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let status: Int32
    public let timedOut: Bool
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case launchFailed(String)
    case temporaryFileFailed(String)
}

public enum ProcessRunner {
    public static func run(_ request: ProcessRequest) throws -> ProcessResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thepfuck-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        } catch {
            throw ProcessRunnerError.temporaryFileFailed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        let stdinURL = directory.appendingPathComponent("stdin")

        do {
            try Data().write(to: stdoutURL)
            if !request.combineOutput { try Data().write(to: stderrURL) }
            if let input = request.stdin { try input.write(to: stdinURL) }
        } catch {
            throw ProcessRunnerError.temporaryFileFailed(error.localizedDescription)
        }

        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let stdinHandle: FileHandle?
        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = request.combineOutput
                ? stdoutHandle
                : try FileHandle(forWritingTo: stderrURL)
            stdinHandle = request.stdin == nil ? nil : try FileHandle(forReadingFrom: stdinURL)
        } catch {
            throw ProcessRunnerError.temporaryFileFailed(error.localizedDescription)
        }
        defer {
            try? stdoutHandle.close()
            if !request.combineOutput { try? stderrHandle.close() }
            try? stdinHandle?.close()
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.standardInput = stdinHandle ?? FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.currentDirectoryURL = request.currentDirectoryURL
        if let additions = request.environment {
            process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, new in new }
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let waitResult = exited.wait(timeout: .now() + max(0, request.timeout))
        let timedOut = waitResult == .timedOut
        if timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.25) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }

        try? stdoutHandle.synchronize()
        if !request.combineOutput { try? stderrHandle.synchronize() }
        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = request.combineOutput
            ? Data()
            : ((try? Data(contentsOf: stderrURL)) ?? Data())
        return ProcessResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
