SIM_NAME ?= iPhone 17
SIM_OS ?= 26.5
DEST = platform=iOS Simulator,name=$(SIM_NAME),OS=$(SIM_OS)
DD = build
XCB = xcodebuild -project AgentHourglassiOS.xcodeproj -scheme AgentHourglassiOS -destination '$(DEST)' -derivedDataPath $(DD) -quiet

APP = $(DD)/Build/Products/Debug-iphonesimulator/AgentHourglass.app
export SIM_NAME SIM_OS

.PHONY: google-config generate build test run-sim render render-widgets mac-ref icon testflight security-pass security-pass-start-log archive

# SPIKE, dev builds only: discover the Antigravity client secret on this Mac into the untracked
# Config/GoogleOAuth.local.xcconfig. testflight.sh refuses to archive while it is set.
google-config:
	cd .. && swift run -c release usagectl google-oauth-xcconfig iOS/Config/GoogleOAuth.local.xcconfig

generate:
	xcodegen generate --quiet

build: generate
	$(XCB) build GIT_COMMIT=$$(git rev-parse --short HEAD)

# One booted, fully booted sim; serial tests; bounded per-test time. See scripts/sim-prepare.sh.
TEST_FLAGS = -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300

test: generate
	udid=$$(scripts/sim-prepare.sh '$(SIM_NAME)' '$(SIM_OS)') && \
	xcodebuild -project AgentHourglassiOS.xcodeproj -scheme AgentHourglassiOS -destination "id=$$udid" -derivedDataPath $(DD) -quiet $(TEST_FLAGS) test GIT_COMMIT=$$(git rev-parse --short HEAD)

run-sim: build
	scripts/run-sim.sh $(APP)

render: render-widgets build
	scripts/render.sh $(APP)

# Headless widget snapshots via ImageRenderer in XCTest; PNGs land in docs/screenshots/widgets.
render-widgets: generate
	rm -rf docs/screenshots/widgets && mkdir -p docs/screenshots/widgets
	TEST_RUNNER_RENDER_OUT=$(abspath docs/screenshots/widgets) $(XCB) test -only-testing:AgentHourglassWidgetTests/RenderMatrixTests

MAC_APP = $(HOME)/Applications/AgentHourglass.app/Contents/MacOS/AgentHourglass

mac-ref:
	mkdir -p $(CURDIR)/$(DD)/mac-ref
	$(MAC_APP) --render-snapshots $(CURDIR)/$(DD)/mac-ref
	$(MAC_APP) --render-states $(CURDIR)/$(DD)/mac-ref
	$(MAC_APP) --render-states $(CURDIR)/$(DD)/mac-ref --theme instrument

icon:
	scripts/make-icon.sh

security-pass-start-log:
	scripts/security-pass.sh --start-log

security-pass:
	scripts/security-pass.sh

archive:
	scripts/testflight.sh --dry-run

testflight:
	scripts/testflight.sh
