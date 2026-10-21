ID ?= FA3D8189AA4D9C1371B314CBDD1278672754EE99
APP := build/Build/Products/Release/AgentHourglass.app

.PHONY: test app sign install hooks icon

icon:
	scripts/make-icon.sh

test:
	swift test
	scripts/secret-scan.sh
	scripts/source-guards.sh

app:
	xcodegen generate --quiet
	xcodebuild -project AgentHourglass.xcodeproj -scheme AgentHourglass -configuration Release \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=YES -quiet build
	scripts/bump-version.sh "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Delete :GitCommit" "$(APP)/Contents/Info.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :GitCommit string $$(git rev-parse --short HEAD)" "$(APP)/Contents/Info.plist"
	$(MAKE) sign ID=$(ID)

sign:
	codesign --force -s "$(ID)" "$(APP)"

install: app
	pkill -x ClaudeUsage || true
	pkill -x AgentHourglass || true
	rm -rf ~/Applications/ClaudeUsage.app ~/Applications/AgentHourglass.app
	mkdir -p ~/Applications
	cp -R "$(APP)" ~/Applications/

hooks:
	mkdir -p .git/hooks
	ln -sf ../../scripts/pre-commit .git/hooks/pre-commit
