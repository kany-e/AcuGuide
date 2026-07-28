# Convenience wrapper so the project is reproducible from the CLI.
#   make project  -> regenerate AcuGuide.xcodeproj from project.yml
#   make build    -> compile-check for a generic iOS device (DEBUG, no signing)
#   make release  -> the build to actually put on a phone (-O, whole-module)
#   make test     -> run the unit-test target on a simulator

.PHONY: project build release test

project:
	xcodegen generate

# DEBUG, and named so. This is the fast compile-check gate, not something to judge the app by.
#
# WHY THIS MATTERS ENOUGH TO SPELL OUT: Debug is `SWIFT_OPTIMIZATION_LEVEL = -Onone`, and this app
# is unusually sensitive to that — it runs CPU triangle raycasts (Möller–Trumbore over mesh
# geometry), One-Euro filters and isotropic hit-tests per camera frame, and builds SceneKit geometry
# for the atlas. Measured on this machine, one raycast-heavy probe
# (BodyMeshProbeTests.testMeasureDetailHandCentreline) runs in 20.8 s at -Onone and 2.1 s at -O:
# a 10× difference on exactly the paths that decide whether the UI feels smooth. A device report of
# "the whole interface is a little bit laggy" from a Debug install is the expected outcome, not a bug.
build: project
	xcodebuild -scheme AcuGuide -destination 'generic/platform=iOS' -configuration Debug \
		CODE_SIGNING_ALLOWED=NO build

# What belongs on a phone. Use this before judging performance or handing a build to anyone.
release: project
	xcodebuild -scheme AcuGuide -destination 'generic/platform=iOS' -configuration Release \
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
