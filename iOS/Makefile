SIM_NAME ?= iPhone 17
SIM_OS ?= 26.0
DEST = platform=iOS Simulator,name=$(SIM_NAME),OS=$(SIM_OS)
DD = build
XCB = xcodebuild -project AgentHourglassiOS.xcodeproj -scheme AgentHourglassiOS -destination '$(DEST)' -derivedDataPath $(DD) -quiet

APP = $(DD)/Build/Products/Debug-iphonesimulator/AgentHourglass.app
export SIM_NAME SIM_OS

.PHONY: generate build test run-sim render icon testflight

generate:
	xcodegen generate --quiet

build: generate
	$(XCB) build GIT_COMMIT=$$(git rev-parse --short HEAD)

test: generate
	$(XCB) test GIT_COMMIT=$$(git rev-parse --short HEAD)

run-sim: build
	scripts/run-sim.sh $(APP)

render: build
	scripts/render.sh $(APP)

icon:
	scripts/make-icon.sh

testflight:
	@echo "testflight: wired in P6 (needs App Store Connect record, distribution cert, API key)"
	@exit 1
