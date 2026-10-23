SIM_NAME ?= iPhone 17
SIM_OS ?= 26.0
DEST = platform=iOS Simulator,name=$(SIM_NAME),OS=$(SIM_OS)
DD = build
XCB = xcodebuild -project AgentHourglassiOS.xcodeproj -scheme AgentHourglassiOS -destination '$(DEST)' -derivedDataPath $(DD) -quiet

.PHONY: generate build test

generate:
	xcodegen generate --quiet

build: generate
	$(XCB) build GIT_COMMIT=$$(git rev-parse --short HEAD)

test: generate
	$(XCB) test GIT_COMMIT=$$(git rev-parse --short HEAD)
