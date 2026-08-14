import ThepfuckCore

func historySelectorTests() -> [TestCase] {
    [
        TestCase(name: "HistorySelector selects newest valid command") {
            let history = "git status\ngit chekout main\nfuck"
            try expectEqual(
                HistorySelector.select(from: history, alias: "fuck"),
                "git chekout main"
            )
        },
        TestCase(name: "HistorySelector removes indentation without retokenizing") {
            let history = "  echo 'a | b' && printf \\\"ü\\\"\n  fuck --yes"
            try expectEqual(
                HistorySelector.select(from: history, alias: "fuck"),
                "echo 'a | b' && printf \\\"ü\\\""
            )
        },
        TestCase(name: "HistorySelector ignores blanks, alias, and executable") {
            let history = """
                git stats

                thepfuck --command 'git stats'
                oops -y
                """
            try expectEqual(
                HistorySelector.select(from: history, alias: "oops"),
                "git stats"
            )
        },
        TestCase(name: "HistorySelector throws when no command remains") {
            try expectThrows(HistorySelectionError.noCommand) {
                _ = try HistorySelector.select(
                    from: "\nfuck\nfuck -y\nthepfuck --history",
                    alias: "fuck"
                )
            }
        },
    ]
}
