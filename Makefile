# Empty ID: resolved from the keychain by team (scripts/mac-sign-id.sh). Override with ID=<sha1>.
ID ?=
NOTARY_PROFILE ?= agent-hourglass
APP := build/Build/Products/Release/AgentHourglass.app

.PHONY: test check-ios app sign install hooks icon release

icon:
	scripts/make-icon.sh

test:
	swift test
	$(MAKE) check-ios
	scripts/secret-scan.sh
	scripts/test-mac-sign-id.sh
	scripts/source-guards.sh
	scripts/test-source-guards.sh

check-ios:
	xcodebuild -workspace . -scheme UsageCore -destination 'generic/platform=iOS Simulator' -derivedDataPath build/check-ios -quiet build

app:
	@[ -n "$(ID)" ] || scripts/mac-sign-id.sh >/dev/null
	xcodegen generate --quiet
	xcodebuild -project AgentHourglass.xcodeproj -scheme AgentHourglass -configuration Release \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=YES -quiet build
	scripts/bump-version.sh "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Delete :GitCommit" "$(APP)/Contents/Info.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :GitCommit string $$(git rev-parse --short HEAD)" "$(APP)/Contents/Info.plist"
	$(MAKE) sign ID=$(ID)

sign:
	@id="$(ID)"; [ -n "$$id" ] || id=$$(scripts/mac-sign-id.sh) || exit 1; \
	  echo "codesign with $$id"; codesign --force --options runtime --timestamp -s "$$id" "$(APP)"
	codesign --verify --strict "$(APP)"
	@codesign -dvv "$(APP)" 2>&1 | grep -q '^TeamIdentifier=[A-Z0-9]\{10\}$$' || { echo "sign: no TeamIdentifier (not a Developer ID build)"; exit 1; }

release: app
	scripts/release.sh "$(APP)" "$(NOTARY_PROFILE)"

install: app
	pkill -x ClaudeUsage || true
	pkill -x AgentHourglass || true
	rm -rf ~/Applications/ClaudeUsage.app ~/Applications/AgentHourglass.app
	mkdir -p ~/Applications
	cp -R "$(APP)" ~/Applications/

hooks:
	mkdir -p .git/hooks
	ln -sf ../../scripts/pre-commit .git/hooks/pre-commit
