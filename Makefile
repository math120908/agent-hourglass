ID ?= FA3D8189AA4D9C1371B314CBDD1278672754EE99
APP := build/Build/Products/Release/ClaudeUsage.app

.PHONY: test app sign install hooks

test:
	swift test
	scripts/secret-scan.sh
	scripts/source-guards.sh

app:
	xcodegen generate --quiet
	xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=YES -quiet build
	$(MAKE) sign ID=$(ID)

sign:
	codesign --force -s "$(ID)" "$(APP)"

install: app
	pkill -x ClaudeUsage || true
	rm -rf ~/Applications/ClaudeUsage.app
	mkdir -p ~/Applications
	cp -R "$(APP)" ~/Applications/

hooks:
	mkdir -p .git/hooks
	ln -sf ../../scripts/pre-commit .git/hooks/pre-commit
