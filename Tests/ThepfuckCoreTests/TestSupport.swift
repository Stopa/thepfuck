import Foundation

struct TestCase {
    let name: String
    let body: () throws -> Void
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw TestFailure(description: "expected \(String(reflecting: expected)), got \(String(reflecting: actual))")
    }
}

func expectTrue(_ condition: @autoclosure () -> Bool) throws {
    guard condition() else {
        throw TestFailure(description: "expected condition to be true")
    }
}

func expectLessThan<T: Comparable>(_ actual: T, _ upperBound: T) throws {
    guard actual < upperBound else {
        throw TestFailure(description: "expected \(actual) to be less than \(upperBound)")
    }
}

func expectContains(_ actual: String, _ fragment: String) throws {
    guard actual.contains(fragment) else {
        throw TestFailure(description: "expected string to contain \(String(reflecting: fragment))")
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw TestFailure(description: message) }
    return value
}

func expectThrows<E: Error & Equatable>(
    _ expected: E,
    _ body: () throws -> Void
) throws {
    do {
        try body()
        throw TestFailure(description: "expected \(expected), but no error was thrown")
    } catch let error as E {
        try expectEqual(error, expected)
    }
}
