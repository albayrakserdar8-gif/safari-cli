# make install: build, put `safari` on PATH, link the skill for Claude Code and opencode.
PREFIX ?= $(shell [ -d /opt/homebrew/bin ] && echo /opt/homebrew || echo /usr/local)
BIN := $(CURDIR)/.build/release/safari
SKILL := $(CURDIR)/Skill/safari-browser
SKILL_DIRS := $(HOME)/.claude/skills $(HOME)/.config/opencode/skills

.PHONY: build install uninstall test test-live

build:
	swift build -c release

install: build
	ln -sf "$(BIN)" "$(PREFIX)/bin/safari"
	@for d in $(SKILL_DIRS); do \
	  if [ -d "$$(dirname "$$d")" ]; then mkdir -p "$$d" && ln -sfn "$(SKILL)" "$$d/safari-browser" && echo "skill → $$d/safari-browser"; fi; \
	done
	@echo "Installed $(PREFIX)/bin/safari. In Claude Code, add \"Bash(safari:*)\" to permissions.allow in ~/.claude/settings.json to skip the prompts."
	@if [ ! -d "$(HOME)/Applications/Safari CLI Bridge.app" ]; then \
	  echo ""; echo "safari needs the Safari CLI Bridge extension, which is not installed yet:"; \
	  echo "  1. Xcode > Settings > Accounts: add an Apple ID (a free one works)"; \
	  echo "  2. open 'Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj', pick your team under Signing & Capabilities for both targets"; \
	  echo "  3. Extension/build.sh --schedule"; \
	  echo "  4. Safari > Settings > Extensions: enable Safari CLI Bridge and allow it on every website"; \
	fi

uninstall:
	-"$(BIN)" stop 2>/dev/null
	@if [ "$$(readlink "$(PREFIX)/bin/safari")" = "$(BIN)" ]; then rm "$(PREFIX)/bin/safari" && echo "removed $(PREFIX)/bin/safari"; fi
	@for d in $(SKILL_DIRS); do \
	  if [ "$$(readlink "$$d/safari-browser")" = "$(SKILL)" ]; then rm "$$d/safari-browser" && echo "removed $$d/safari-browser"; fi; \
	done

# Local checks (no CI): build, page-script syntax, CLI and daemon smoke test.
test: build
	awk '/static let source = #"""/{f=1;next} /^    """#/{f=0} f' Sources/safari/PageAgent.swift > "$${TMPDIR:-/tmp}/safari-agent.js"
	node --check "$${TMPDIR:-/tmp}/safari-agent.js"
	awk '/static let mainSource = #"""/{f=1;next} /^    """#/{f=0} f' Sources/safari/PageAgent.swift > "$${TMPDIR:-/tmp}/safari-main.js"
	node --check "$${TMPDIR:-/tmp}/safari-main.js"
	Tests/smoke.sh

# Live check against the real Safari (not part of `test`): needs the extension on; opens background tabs and closes them.
test-live: build
	Tests/live.sh
