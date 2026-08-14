import ThepfuckCore

func cliOptionsTests() -> [TestCase] {
    [
        TestCase(name: "CLIOptions parses default alias using current shell") {
            let options = try CLIOptions.parse(
                arguments: ["--alias"],
                environment: ["SHELL": "/bin/zsh"]
            )
            try expectEqual(options.mode, .alias)
            try expectEqual(options.aliasName, "fuck")
            try expectEqual(options.shell, .zsh)
            try expectEqual(options.shellPath, "/bin/zsh")
        },
        TestCase(name: "CLIOptions parses custom alias and explicit shell") {
            let options = try CLIOptions.parse(
                arguments: ["--alias", "FUCK", "--shell", "bash"],
                environment: ["SHELL": "/opt/homebrew/bin/zsh"]
            )
            try expectEqual(options.aliasName, "FUCK")
            try expectEqual(options.shell, .bash)
            try expectEqual(options.shellPath, "/bin/bash")
        },
        TestCase(name: "CLIOptions parses generated history invocation") {
            let options = try CLIOptions.parse(
                arguments: [
                    "--history", "--shell", "zsh", "--alias-name", "oops",
                    "--yes", "--timeout", "1.5",
                ],
                environment: ["SHELL": "/bin/zsh"]
            )
            try expectEqual(options.mode, .correct)
            try expectEqual(options.readHistory, true)
            try expectEqual(options.aliasName, "oops")
            try expectEqual(options.yes, true)
            try expectEqual(options.commandTimeout, 1.5)
        },
        TestCase(name: "CLIOptions preserves explicit command as one value") {
            let command = "printf 'a | b' && echo ü"
            let options = try CLIOptions.parse(
                arguments: ["--command", command],
                environment: ["SHELL": "/bin/bash"]
            )
            try expectEqual(options.command, command)
            try expectEqual(options.shell, .bash)
        },
        TestCase(name: "CLIOptions rejects history command conflict") {
            try expectThrows(CLIOptionsError.conflictingCommandSources) {
                _ = try CLIOptions.parse(
                    arguments: ["--history", "--command", "bad"],
                    environment: ["SHELL": "/bin/zsh"]
                )
            }
        },
        TestCase(name: "CLIOptions rejects invalid timeout") {
            try expectThrows(CLIOptionsError.invalidTimeout("zero")) {
                _ = try CLIOptions.parse(
                    arguments: ["--history", "--timeout", "zero"],
                    environment: ["SHELL": "/bin/zsh"]
                )
            }
        },
        TestCase(name: "CLIOptions rejects unknown option") {
            try expectThrows(CLIOptionsError.unknownOption("--wat")) {
                _ = try CLIOptions.parse(
                    arguments: ["--wat"],
                    environment: ["SHELL": "/bin/zsh"]
                )
            }
        },
        TestCase(name: "CLIOptions rejects command mode without source") {
            try expectThrows(CLIOptionsError.noCommandSource) {
                _ = try CLIOptions.parse(arguments: [], environment: ["SHELL": "/bin/zsh"])
            }
        },
        TestCase(name: "CLIOptions help does not require SHELL") {
            let options = try CLIOptions.parse(arguments: ["--help"], environment: [:])
            try expectEqual(options.mode, .help)
        },
    ]
}
