import Foundation

let allTests = historySelectorTests()
    + aliasExpanderTests()
    + correctionRequestTests()
    + processRunnerTests()
    + shellIntegrationTests()
    + correctionServiceTests()
    + clientTests()
    + cliOptionsTests()
let filter = CommandLine.arguments.dropFirst().first
let selected = allTests.filter { test in
    filter.map { test.name.localizedCaseInsensitiveContains($0) } ?? true
}

var failures = 0
for test in selected {
    do {
        try test.body()
        print("PASS \(test.name)")
    } catch {
        failures += 1
        print("FAIL \(test.name): \(error)")
    }
}

print("\(selected.count - failures) passed, \(failures) failed")
if failures > 0 || selected.isEmpty {
    exit(1)
}
