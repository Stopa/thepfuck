import ThepfuckCore

func aliasExpanderTests() -> [TestCase] {
    [
        TestCase(name: "AliasExpander expands a zsh leading alias") {
            let expanded = AliasExpander.expand(
                command: "g pull --rebase",
                definitions: "g=git\nll='ls -alF'",
                shell: .zsh
            )
            try expectEqual(expanded, "git pull --rebase")
        },
        TestCase(name: "AliasExpander expands a Bash leading alias") {
            let expanded = AliasExpander.expand(
                command: "ll /tmp",
                definitions: "alias g='git'\nalias ll='ls -alF'",
                shell: .bash
            )
            try expectEqual(expanded, "ls -alF /tmp")
        },
        TestCase(name: "AliasExpander leaves unknown commands unchanged") {
            let expanded = AliasExpander.expand(
                command: "git status",
                definitions: "g=git",
                shell: .zsh
            )
            try expectEqual(expanded, "git status")
        },
        TestCase(name: "AliasExpander only expands the command's first token") {
            let expanded = AliasExpander.expand(
                command: "printf '%s' g",
                definitions: "g=git",
                shell: .zsh
            )
            try expectEqual(expanded, "printf '%s' g")
        },
    ]
}
