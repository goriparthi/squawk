# Squawk. The Swift build needs only the Command Line Tools; XCTest needs Xcode.
.PHONY: help build test smoke icon bundle dmg install run uninstall install-hook clean

help:
	@echo "  make test          offline unit suite"
	@echo "  make smoke         end to end hook protocol check"
	@echo "  make icon          re-render the icon and menu bar glyph from design/"
	@echo "  make bundle        assemble dist/Squawk.app"
	@echo "  make dmg           build dist/Squawk-<version>.dmg, notarized when configured"
	@echo "  make install       build and copy to ~/Applications"
	@echo "  make run           install and launch"
	@echo "  make install-hook  register the PreToolUse hook in ~/.claude/settings.json"
	@echo "  make uninstall     remove the installed app"
	@echo "  make clean         remove build products"

build:
	@swift build --package-path app

test:
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path app

smoke: build
	@scripts/smoke.sh

icon:
	@scripts/render-icon.sh

bundle:
	@scripts/bundle.sh

dmg:
	@scripts/package-dmg.sh

install: bundle
	@mkdir -p $(HOME)/Applications
	@rm -rf $(HOME)/Applications/Squawk.app
	@cp -R dist/Squawk.app $(HOME)/Applications/Squawk.app
	@echo "installed to ~/Applications/Squawk.app"

run: install
	@open $(HOME)/Applications/Squawk.app

install-hook:
	@scripts/install-hook.sh

uninstall:
	@rm -rf $(HOME)/Applications/Squawk.app
	@echo "removed ~/Applications/Squawk.app"

clean:
	@rm -rf app/.build dist
