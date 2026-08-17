import ThepfuckCore

func shellIntegrationTests() -> [TestCase] {
    [
        TestCase(name: "ShellKind detects zsh and bash paths") {
            try expectEqual(try ShellKind.detect(from: "/bin/zsh"), .zsh)
            try expectEqual(try ShellKind.detect(from: "/opt/homebrew/bin/bash"), .bash)
        },
        TestCase(name: "ShellKind rejects fish honestly") {
            try expectThrows(ShellIntegrationError.unsupportedShell("fish")) {
                _ = try ShellKind.detect(from: "/opt/homebrew/bin/fish")
            }
        },
        TestCase(name: "ShellIntegration rejects unsafe alias interpolation") {
            try expectThrows(ShellIntegrationError.invalidAlias("bad; rm")) {
                _ = try ShellIntegration.render(shell: .zsh, alias: "bad; rm")
            }
        },
        TestCase(name: "ShellIntegration renders zsh parent-shell flow") {
            let source = try ShellIntegration.render(shell: .zsh, alias: "fuck")
            try expectContains(source, "fuck() {")
            try expectContains(source, "fc -ln -10")
            try expectContains(source, "thepfuck_aliases=\"$(alias)\"")
            try expectContains(
                source,
                "THEPFUCK_CAPTURED_ALIASES=\"$thepfuck_aliases\" command thepfuck"
            )
            try expectContains(source, "command thepfuck --history --shell zsh --alias-name fuck")
            try expectContains(source, "\"$@\"")
            try expectContains(source, "print -s -- \"$thepfuck_command\"")
            try expectContains(source, "eval \"$thepfuck_command\"")
        },
        TestCase(name: "ShellIntegration renders bash parent-shell flow") {
            let source = try ShellIntegration.render(shell: .bash, alias: "FUCK")
            try expectContains(source, "function FUCK() {")
            try expectContains(source, "builtin history 10 | sed")
            try expectContains(source, "thepfuck_aliases=\"$(alias)\"")
            try expectContains(
                source,
                "THEPFUCK_CAPTURED_ALIASES=\"$thepfuck_aliases\" command thepfuck"
            )
            try expectContains(source, "command thepfuck --history --shell bash --alias-name FUCK")
            try expectContains(source, "history -s \"$thepfuck_command\"")
            try expectContains(source, "eval \"$thepfuck_command\"")
        },
    ]
}
