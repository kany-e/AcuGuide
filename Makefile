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
# can't fail on a machine that simply doesn't have the hardcoded device installed. The discovery
# lives in scripts/pick_simulator.sh because the pattern needs a literal "(" — inline in $(shell)
# that unbalanced paren made make abort with "unterminated call to function `shell'".
SIM ?= $(shell scripts/pick_simulator.sh)

test: project
	@test -n "$(SIM)" || { \
		echo "No available iPhone simulator found. Install one in Xcode, or run: make test SIM='iPhone 16'"; \
		exit 1; }
	xcodebuild -scheme AcuGuide \
		-destination "platform=iOS Simulator,name=$(SIM)" test
