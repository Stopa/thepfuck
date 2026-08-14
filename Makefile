PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin

.PHONY: build test install uninstall

build:
	swift build -c release

test:
	swift run thepfuck-tests
	swift build
	bash Tests/Integration/cli_test.sh .build/debug/thepfuck

install: build
	install -d "$(BINDIR)"
	install -m 755 .build/release/thepfuck "$(BINDIR)/thepfuck"

uninstall:
	rm -f "$(BINDIR)/thepfuck"
