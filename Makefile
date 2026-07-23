# Convenience wrapper so the project is reproducible from the CLI.
#   make project  -> regenerate AcuGuide.xcodeproj from project.yml
#   make build    -> build for a generic iOS device (no signing)
#   make test     -> run the unit-test target on a simulator

.PHONY: project build test

project:
	xcodegen generate

build: project
	xcodebuild -scheme AcuGuide -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO build

# SIM overrides the simulator; the default auto-discovers one the way CI does, so `make test`
# can't fail on a machine that simply doesn't have the hardcoded device installed.
SIM ?= $(shell xcrun simctl list devices available | grep -m1 -oE 'iPhone [0-9]+[^(]*' | head -1 | xargs)

test: project
	xcodebuild -scheme AcuGuide \
		-destination "platform=iOS Simulator,name=$(SIM)" test
